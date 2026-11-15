/* Standalone virtual-controller tests. See scripts/test_macos_gamepad.sh.
 * A separate, AppKit-initialized process verifies actual native input changes.
 * --monitor observes a running Lumina without creating or signing a device.
 */
#import "hid_gamepad.h"
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#include <math.h>
#include <poll.h>
#include <stdio.h>

static void pump(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void prepareNativeClient(void) {
    // Exercise the framework in an application context, not just a Foundation
    // command-line process. Do not activate the app or steal the user's focus.
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    [GCController setShouldMonitorBackgroundEvents:YES];
}

static NSString *nativeState(GCController *controller) {
    GCExtendedGamepad *pad = controller.extendedGamepad;
    return [NSString stringWithFormat:@"%@ / %@ t=%.6f: A=%.2f L1=%.2f dpad=(%.2f,%.2f) L=(%.2f,%.2f) R=(%.2f,%.2f) LT=%.2f RT=%.2f",
        controller.vendorName, NSStringFromClass([pad class]), controller.physicalInputProfile.lastEventTimestamp,
        pad.buttonA.value, pad.leftShoulder.value, pad.dpad.xAxis.value, pad.dpad.yAxis.value,
        pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value,
        pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value,
        pad.leftTrigger.value, pad.rightTrigger.value];
}

static void logNativeEvents(GCController *controller) {
    // Poll and callbacks are independent observations. Use a serial queue so a
    // busy main thread cannot hide callbacks, without retaining the controller
    // in its own profile's block.
    dispatch_queue_t queue = dispatch_queue_create("com.lumina.test.native-events", DISPATCH_QUEUE_SERIAL);
    controller.handlerQueue = queue;
    dispatch_release(queue);
    NSString *name = controller.vendorName;
    controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        NSLog(@"Native callback %@: A=%.2f L=(%.2f,%.2f) LT=%.2f", name,
              pad.buttonA.value, pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value,
              pad.leftTrigger.value);
    };
}

static int monitor(void) {
    prepareNativeClient();
    NSLog(@"Monitoring native input for 25 seconds; operate the Moonlight controller.");
    NSTimer *heartbeat = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        NSLog(@"Native monitor heartbeat: controllers=%lu", (unsigned long)[GCController controllers].count);
    }];
    NSMutableSet *watched = [NSMutableSet set];
    NSString *last = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:25];
    while ([deadline timeIntervalSinceNow] > 0) {
        pump(0.02);
        NSArray *controllers = [GCController controllers];
        NSMutableArray *states = [NSMutableArray arrayWithObject:
            [NSString stringWithFormat:@"controllers=%lu", (unsigned long)controllers.count]];
        for (GCController *controller in controllers) {
            if (![watched containsObject:controller]) {
                [watched addObject:controller];
                logNativeEvents(controller);
            }
            [states addObject:nativeState(controller)];
        }
        NSString *state = [states componentsJoinedByString:@"\n"];
        if (![state isEqualToString:last]) {
            NSLog(@"%@", state);
            [last release];
            last = [state copy];
        }
    }
    [heartbeat invalidate];
    for (GCController *controller in watched) controller.extendedGamepad.valueChangedHandler = nil;
    [last release];
    return 0;
}

static BOOL testHIDReports(HIDGamepadProfile profile) {
    BOOL xbox = profile == HIDGamepadProfileXbox;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    NSDictionary *matching = @{
        @kIOHIDVendorIDKey: @(xbox ? 0x045e : 0x054c),
        @kIOHIDProductIDKey: @(xbox ? 0x02fd : 0x0ce6),
        @kIOHIDSerialNumberKey: xbox ? @"LUMINA-XB-15" : @"LUMINA-DS-15"
    };
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)matching);
    IOReturn result = IOHIDManagerOpen(manager, 0);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    BOOL passed = NO;
    if (result == kIOReturnSuccess && devices && CFSetGetCount(devices) == 1) {
        IOHIDDeviceRef device;
        CFSetGetValues(devices, (const void **)&device);
        result = IOHIDDeviceOpen(device, 0);
        if (result == kIOReturnSuccess) {
            uint8_t bytes[64] = {0};
            CFIndex length = sizeof(bytes);
            result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 1, bytes, &length);
            if (xbox) {
                HIDXboxReport neutral = xboxReport(0, 0, 0, 0, 0, 0, 0);
                passed = result == kIOReturnSuccess && length == sizeof(neutral) &&
                         memcmp(bytes, &neutral, sizeof(neutral)) == 0;
                length = sizeof(bytes);
                result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 2, bytes, &length);
                passed = passed && result == kIOReturnSuccess && length == 2 && bytes[0] == 2 && bytes[1] == 0;
            } else {
                HIDGamepadReport neutral = dualSenseReport(0, 0, 0, 0, 0, 0, 0);
                passed = result == kIOReturnSuccess && length == sizeof(neutral) &&
                         memcmp(bytes, &neutral, sizeof(neutral)) == 0;
                for (unsigned id = 0; id < 256 && passed; ++id) {
                    uint8_t expected[64];
                    size_t expectedLength = dualSenseFeatureReport(id, expected, 15);
                    if (!expectedLength) continue;
                    length = sizeof(bytes);
                    result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, id, bytes, &length);
                    passed = result == kIOReturnSuccess && length == (CFIndex)expectedLength &&
                             memcmp(bytes, expected, expectedLength) == 0;
                    if (!passed) NSLog(@"FAIL: GET feature %02x result=0x%x length=%ld", id, result, length);
                }
            }
            IOHIDDeviceClose(device, 0);
        }
    }
    if (devices) CFRelease(devices);
    IOHIDManagerClose(manager, 0);
    CFRelease(manager);
    NSLog(@"Raw HID enumeration / GET_REPORT: %@ (last result=0x%x)", passed ? @"PASS" : @"FAIL", result);
    return passed;
}

static int observe(HIDGamepadProfile profile) {
    prepareNativeClient();
    NSSet *existing = [NSSet setWithArray:[GCController controllers]];
    GCController *controller = nil;
    BOOL sawPress = NO, sawRelease = NO;
    // Signal readiness before the parent creates the test device. This also
    // makes it safe to exclude existing controllers instead of matching a name
    // that macOS may normalize to Sony/Microsoft.
    printf("READY\n");
    fflush(stdout);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while ([deadline timeIntervalSinceNow] > 0) {
        pump(0.02);
        if (!controller) {
            for (GCController *candidate in [GCController controllers]) {
                if ([existing containsObject:candidate]) continue;
                Class expected = profile == HIDGamepadProfileXbox ? [GCXboxGamepad class] : [GCDualSenseGamepad class];
                if (![candidate.extendedGamepad isKindOfClass:expected]) continue;
                controller = [candidate retain];
                logNativeEvents(controller);
                NSLog(@"Native observer found %@ / %@", controller.vendorName,
                      NSStringFromClass([controller.extendedGamepad class]));
                break;
            }
        }
        if (!controller) continue;
        GCExtendedGamepad *pad = controller.extendedGamepad;
        if (pad.buttonA.isPressed && pad.leftShoulder.isPressed &&
            pad.dpad.up.isPressed && pad.dpad.right.isPressed &&
            pad.leftThumbstick.xAxis.value > 0.95 && pad.leftThumbstick.yAxis.value > 0.95 &&
            pad.rightThumbstick.xAxis.value < -0.95 && pad.rightThumbstick.yAxis.value < -0.95 &&
            fabsf(pad.leftTrigger.value - 64.0f / 255) < 0.03 &&
            fabsf(pad.rightTrigger.value - 192.0f / 255) < 0.03) {
            if (!sawPress) NSLog(@"Native press received: %@", nativeState(controller));
            sawPress = YES;
        }
        if (sawPress && !pad.buttonA.isPressed && !pad.leftShoulder.isPressed &&
            !pad.dpad.up.isPressed && !pad.dpad.right.isPressed &&
            fabsf(pad.leftThumbstick.xAxis.value) < 0.03 && fabsf(pad.leftThumbstick.yAxis.value) < 0.03 &&
            fabsf(pad.rightThumbstick.xAxis.value) < 0.03 && fabsf(pad.rightThumbstick.yAxis.value) < 0.03 &&
            pad.leftTrigger.value < 0.01 && pad.rightTrigger.value < 0.01) {
            if (!sawRelease) NSLog(@"Native release received");
            sawRelease = YES;
        }
        if (![[GCController controllers] containsObject:controller]) {
            NSLog(@"Native observer: press=%d release=%d removed=1", sawPress, sawRelease);
            [controller release];
            return sawPress && sawRelease ? 0 : 1;
        }
    }
    NSLog(@"FAIL: native observer timed out (controller=%@ press=%d release=%d)",
          controller.vendorName, sawPress, sawRelease);
    if (controller) NSLog(@"Last state: %@", nativeState(controller));
    for (GCController *candidate in [GCController controllers]) {
        NSLog(@"Enumerated: %@ category=%@", nativeState(candidate), candidate.productCategory);
    }
    [controller release];
    return 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        HIDGamepadProfile profile = [HIDGamepad defaultProfile];
        BOOL observing = NO;
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--monitor") == 0) return monitor();
            if (strcmp(argv[i], "--observe") == 0) observing = YES;
            else if (strcmp(argv[i], "--profile=xbox") == 0) profile = HIDGamepadProfileXbox;
            else if (strcmp(argv[i], "--profile=ds5") == 0) profile = HIDGamepadProfileDualSense;
            else if (strcmp(argv[i], "--profile=auto") != 0) {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                return 2;
            }
        }
        if (observing) return observe(profile);
        NSString *profileOption = profile == HIDGamepadProfileXbox ? @"--profile=xbox" : @"--profile=ds5";
        NSLog(@"Integration test: %@", profileOption);
        NSTask *observer = [[NSTask alloc] init];
        observer.executableURL = [NSURL fileURLWithPath:[[NSProcessInfo processInfo] arguments][0]];
        observer.arguments = @[@"--observe", profileOption];
        NSPipe *ready = [NSPipe pipe];
        observer.standardOutput = ready;
        NSError *error = nil;
        if (![observer launchAndReturnError:&error]) {
            NSLog(@"FAIL: cannot start observer: %@", error);
            [observer release];
            return 1;
        }
        struct pollfd descriptor = {ready.fileHandleForReading.fileDescriptor, POLLIN, 0};
        if (poll(&descriptor, 1, 10000) <= 0 || !(descriptor.revents & POLLIN) ||
            ![[ready.fileHandleForReading readDataOfLength:6] isEqualToData:[@"READY\n" dataUsingEncoding:NSUTF8StringEncoding]]) {
            NSLog(@"FAIL: native observer did not become ready");
            if (observer.running) [observer terminate];
            [observer waitUntilExit];
            [observer release];
            return 1;
        }
        HIDGamepad *device = [[HIDGamepad alloc] initWithIndex:15 profile:profile];
        if (![device createDevice]) {
            NSLog(@"SKIP: test device creation denied; verify this test binary's HID signing entitlement");
            [observer terminate];
            [observer waitUntilExit];
            [observer release];
            [device release];
            return 77;
        }
        pump(0.5);
        BOOL rawHIDPassed = testHIDReports(profile);
        // Send transitions after observer startup, without Moonlight or a
        // physical controller. Enumeration alone must never pass this test.
        for (unsigned i = 0; i < 120; ++i) {
            BOOL pressed = (i / 5) % 2;
            [device updateState:pressed ? (0x1000 | 0x0100 | 0x0001 | 0x0008) : 0
                     leftStickX:pressed ? INT16_MAX : 0
                     leftStickY:pressed ? INT16_MAX : 0
                    rightStickX:pressed ? INT16_MIN : 0
                    rightStickY:pressed ? INT16_MIN : 0
                    leftTrigger:pressed ? 64 : 0
                   rightTrigger:pressed ? 192 : 0];
            pump(0.05);
        }
        [device disconnect];
        [device release];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
        while (observer.running && [deadline timeIntervalSinceNow] > 0) pump(0.05);
        if (observer.running) {
            [observer terminate];
            [observer waitUntilExit];
            [observer release];
            NSLog(@"FAIL: observer did not finish");
            return 1;
        }
        int status = observer.terminationStatus;
        [observer release];
        if (!status && rawHIDPassed) puts("Independent-process native controller recognition/input/removal test passed");
        return status || !rawHIDPassed ? 1 : 0;
    }
}
