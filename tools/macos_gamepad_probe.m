/* Read-only DualSense diagnostics: live HID reports, HID elements and native GC.
 * Does not create a device, seize it, issue get/set reports, or change settings.
 * Run using scripts/diagnose_macos_gamepad.sh while Lumina is streaming.
 */
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <string.h>

@interface ProbeState : NSObject
@property NSUInteger rawCount;
@property NSUInteger valueCount;
@property NSUInteger nativeCount;
@property NSUInteger rawErrors;
@property NSUInteger valueErrors;
@property NSUInteger matched;
@property NSTimeInterval lastRawTime;
@property NSData *lastRaw;
@property uint32_t reportID;
@property NSInteger cross;
@property NSInteger lx;
@property NSInteger ly;
@property NSInteger lt;
@property NSMutableSet<GCController *> *watched;
@end
@implementation ProbeState
@end

static NSTimeInterval now(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void deviceMatched(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)sender;
    ProbeState *state = (__bridge ProbeState *)context;
    if (result != kIOReturnSuccess) {
        NSLog(@"HID match failed: 0x%x", result);
        return;
    }
    ++state.matched;
    uint64_t registryID = 0;
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID);
    NSLog(@"HID attached: registry=0x%llx product=%@ transport=%@", registryID,
          (__bridge id)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)),
          (__bridge id)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDTransportKey)));
}

static void deviceRemoved(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)result; (void)sender; (void)device;
    ProbeState *state = (__bridge ProbeState *)context;
    if (state.matched) --state.matched;
    // Do not show a removed device's stale state as current input.
    state.lastRaw = nil;
    state.cross = state.lx = state.ly = state.lt = -1;
    NSLog(@"HID removed");
}

static void rawInput(void *context, IOReturn result, void *sender,
        IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex length) {
    (void)sender;
    ProbeState *state = (__bridge ProbeState *)context;
    if (result != kIOReturnSuccess) { ++state.rawErrors; return; }
    if (type != kIOHIDReportTypeInput || length < 0) return;
    ++state.rawCount;
    state.lastRawTime = now();
    state.reportID = reportID;
    state.lastRaw = [NSData dataWithBytes:report length:(NSUInteger)length];
}

static void elementInput(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    (void)sender;
    ProbeState *state = (__bridge ProbeState *)context;
    if (result != kIOReturnSuccess) { ++state.valueErrors; return; }
    ++state.valueCount;
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    if (!((page == 9 && usage == 2) ||
          (page == 1 && (usage == 0x30 || usage == 0x31 || usage == 0x33)))) return;
    NSInteger number = IOHIDValueGetIntegerValue(value);
    if (page == 9) state.cross = number;
    else if (usage == 0x30) state.lx = number;
    else if (usage == 0x31) state.ly = number;
    else state.lt = number;
}

static NSString *hexPrefix(NSData *data) {
    if (!data) return @"(no report received)";
    NSMutableString *text = [NSMutableString string];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < MIN(data.length, 16); ++i) [text appendFormat:@"%02x ", bytes[i]];
    return text;
}

static void watchNative(ProbeState *state) {
    for (GCController *controller in GCController.controllers) {
        if (![controller.productCategory isEqualToString:@"DualSense"] ||
            [state.watched containsObject:controller]) continue;
        [state.watched addObject:controller];
        controller.handlerQueue = dispatch_get_main_queue();
        // Weak state avoids state -> controller -> handler -> state retention.
        __weak ProbeState *weakState = state;
        controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
            (void)pad; (void)element;
            ProbeState *strongState = weakState;
            if (strongState) ++strongState.nativeCount;
        };
        NSLog(@"GC attached: vendor=%@ category=%@ profile=%@", controller.vendorName,
              controller.productCategory, NSStringFromClass(controller.extendedGamepad.class));
    }
}

static void snapshot(ProbeState *state) {
    watchNative(state);
    NSLog(@"HEARTBEAT t=%.3f active=%d HID.devices=%lu raw=%lu values=%lu GC.callbacks=%lu errors(raw/value)=%lu/%lu",
          now(), NSApp.isActive, state.matched, state.rawCount, state.valueCount,
          state.nativeCount, state.rawErrors, state.valueErrors);
    NSLog(@"RAW age=%.3f ID=%u length=%lu first16=%@", state.lastRaw ? now() - state.lastRawTime : -1,
          state.reportID, state.lastRaw.length, hexPrefix(state.lastRaw));
    NSLog(@"HID elements: Cross=%ld LX=%ld LY=%ld LT=%ld (-1 means not observed)",
          (long)state.cross, (long)state.lx, (long)state.ly, (long)state.lt);
    for (GCController *controller in GCController.controllers) {
        if (![controller.productCategory isEqualToString:@"DualSense"]) continue;
        GCExtendedGamepad *pad = controller.extendedGamepad;
        NSLog(@"GC %@: lastEvent=%.6f A=%.3f L=(%.3f,%.3f) LT=%.3f", controller.vendorName,
              controller.physicalInputProfile.lastEventTimestamp, pad.buttonA.value,
              pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value, pad.leftTrigger.value);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL foreground = NO;
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--foreground") != 0) {
                fprintf(stderr, "Usage: macos-gamepad-probe [--foreground]\n");
                return 2;
            }
            foreground = YES;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:foreground ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
        [GCController setShouldMonitorBackgroundEvents:YES];
        [NSApp finishLaunching];
        NSWindow *window = nil;
        if (foreground) {
            window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 560, 140)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            window.title = @"Lumina input probe — keep this window focused";
            NSTextField *label = [NSTextField labelWithString:@"Hold A/Cross for 2 seconds; release.\nMove the left stick; squeeze the left trigger.\nResults are printed in the terminal for 30 seconds."];
            label.frame = NSMakeRect(20, 20, 520, 100);
            [window.contentView addSubview:label];
            [window makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
        }
        ProbeState *state = [ProbeState new];
        state.watched = [NSMutableSet set];
        state.cross = state.lx = state.ly = state.lt = -1;
        IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
        NSDictionary *match = @{
            @kIOHIDVendorIDKey: @0x054c, @kIOHIDProductIDKey: @0x0ce6,
            @kIOHIDSerialNumberKey: @"LUMINA-DS-0",
        };
        IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)match);
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, (__bridge void *)state);
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, (__bridge void *)state);
        IOHIDManagerRegisterInputReportCallback(manager, rawInput, (__bridge void *)state);
        IOHIDManagerRegisterInputValueCallback(manager, elementInput, (__bridge void *)state);
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        IOReturn opened = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
        NSLog(@"OS: %@; PID=%d; mode=%@; HID open=0x%x (no exclusive access)",
              NSProcessInfo.processInfo.operatingSystemVersionString, NSProcessInfo.processInfo.processIdentifier,
              foreground ? @"foreground window" : @"background", opened);
        if (opened != kIOReturnSuccess) {
            NSLog(@"HID access failed; do not interpret missing reports as a controller protocol failure.");
        }
        watchNative(state);
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *unused) {
            (void)unused;
            snapshot(state);
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while (deadline.timeIntervalSinceNow > 0) {
            // Pump AppKit events as well as the main run loop; foreground mode
            // provides a positive control for process/focus routing differences.
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
        [timer invalidate];
        snapshot(state);
        for (GCController *controller in state.watched) controller.extendedGamepad.valueChangedHandler = nil;
        IOHIDManagerClose(manager, 0);
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        CFRelease(manager);
        [window orderOut:nil];
        NSLog(@"DONE: counts are diagnostic observations, not a compatibility pass/fail.");
        return opened == kIOReturnSuccess ? 0 : 1;
    }
}
