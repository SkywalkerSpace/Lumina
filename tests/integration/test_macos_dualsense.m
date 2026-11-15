/* Standalone macOS integration test. See scripts/test_macos_gamepad.sh.
 * Uses a second process to verify native GameController enumeration, real
 * input transitions and removal, not just successful HID publication.
 */
#import "hid_gamepad.h"
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#include <math.h>
#include <stdio.h>

static void pump(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL testHIDReports(void) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    NSDictionary *matching = @{
        @kIOHIDVendorIDKey: @(0x054c), @kIOHIDProductIDKey: @(0x0ce6),
        @kIOHIDSerialNumberKey: @"X360W-D16"
    };
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)matching);
    IOReturn result = IOHIDManagerOpen(manager, 0);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    BOOL passed = NO;
    if (result == kIOReturnSuccess && devices && CFSetGetCount(devices) == 1) {
        IOHIDDeviceRef device;
        CFSetGetValues(devices, (const void **)&device);
        CFStringRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
        passed = product && CFStringCompare(product, CFSTR("Wireless Controller"), 0) == kCFCompareEqualTo;
        result = IOHIDDeviceOpen(device, 0);
        if (result == kIOReturnSuccess && passed) {
            uint8_t bytes[64] = {0};
            CFIndex length = sizeof(bytes);
            result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 1, bytes, &length);
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
            IOHIDDeviceClose(device, 0);
        }
    }
    if (devices) CFRelease(devices);
    IOHIDManagerClose(manager, 0);
    CFRelease(manager);
    NSLog(@"Raw HID enumeration / GET_REPORT: %@ (last result=0x%x)", passed ? @"PASS" : @"FAIL", result);
    return passed;
}

static int observe(void) {
    [GCController setShouldMonitorBackgroundEvents:YES];
    GCController *controller = nil;
    BOOL sawPress = NO, sawRelease = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while ([deadline timeIntervalSinceNow] > 0) {
        pump(0.02);
        if (!controller) {
            for (GCController *candidate in [GCController controllers]) {
                if ([candidate.vendorName containsString:@"Sony"] ||
                    [candidate.vendorName containsString:@"DualSense"]) {
                    controller = [candidate retain];
                    NSLog(@"Native observer found %@ / %@", controller.vendorName,
                          NSStringFromClass([controller.extendedGamepad class]));
                    if (![controller.extendedGamepad isKindOfClass:[GCDualSenseGamepad class]]) {
                        NSLog(@"FAIL: native profile is not GCDualSenseGamepad");
                        [controller release];
                        return 1;
                    }
                    break;
                }
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
            sawPress = YES;
        }
        if (sawPress && !pad.buttonA.isPressed && !pad.leftShoulder.isPressed &&
            !pad.dpad.up.isPressed && !pad.dpad.right.isPressed &&
            fabsf(pad.leftThumbstick.xAxis.value) < 0.03 &&
            fabsf(pad.leftThumbstick.yAxis.value) < 0.03 &&
            fabsf(pad.rightThumbstick.xAxis.value) < 0.03 &&
            fabsf(pad.rightThumbstick.yAxis.value) < 0.03 &&
            pad.leftTrigger.value < 0.01 && pad.rightTrigger.value < 0.01) {
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
    if (controller) {
        GCExtendedGamepad *pad = controller.extendedGamepad;
        NSLog(@"Last state: A=%d L1=%d dpad=(%.2f,%.2f) L=(%.2f,%.2f) R=(%.2f,%.2f) triggers=(%.2f,%.2f)",
              pad.buttonA.isPressed, pad.leftShoulder.isPressed, pad.dpad.xAxis.value, pad.dpad.yAxis.value,
              pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value,
              pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value,
              pad.leftTrigger.value, pad.rightTrigger.value);
    }
    [controller release];
    return 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--observe") == 0) return observe();
        if (![HIDGamepad isAvailable]) {
            NSLog(@"SKIP: virtual HID device creation denied; verify the test binary's signing entitlement");
            return 77;
        }
        NSTask *observer = [[NSTask alloc] init];
        observer.executableURL = [NSURL fileURLWithPath:[[NSProcessInfo processInfo] arguments][0]];
        observer.arguments = @[@"--observe"];
        NSError *error = nil;
        if (![observer launchAndReturnError:&error]) {
            NSLog(@"FAIL: cannot start observer: %@", error);
            [observer release];
            return 1;
        }
        pump(0.5);
        HIDGamepad *device = [[HIDGamepad alloc] initWithIndex:15];
        if (![device createDevice]) {
            [observer terminate];
            [observer waitUntilExit];
            [observer release];
            [device release];
            return 1;
        }
        pump(0.5);
        BOOL rawHIDPassed = testHIDReports();
        // Continue transitions after the observer attaches; applications need
        // not receive a snapshot of input held before they started observing.
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
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
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
        if (!status) puts("Independent-process native DualSense recognition/input/removal test passed");
        return status || !rawHIDPassed ? 1 : 0;
    }
}
