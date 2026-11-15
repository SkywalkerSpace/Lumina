/**
 * @file src/platform/macos/hid_gamepad.m
 * @brief USB DualSense-compatible virtual gamepad via IOHIDUserDevice.
 * @details Requires com.apple.developer.hid.virtual.device in the executable's
 *          effective signing entitlements. No system security settings are changed.
 */
#import "hid_gamepad.h"
#import <mach/mach_time.h>
#import <dlfcn.h>
#import <Block.h>
#include <stdio.h>

// x360w uses the callback registration entry points (rather than the newer
// block wrappers). Resolve them dynamically because they are not declared by
// the public SDK header on every supported macOS SDK.
typedef IOReturn (*HIDReportCallback)(void *context, int type, uint32_t reportID,
                                      uint8_t *report, CFIndex reportLength);
typedef void (*HIDRegisterReportCallback)(IOHIDUserDeviceRef device,
                                          HIDReportCallback callback, void *context);

typedef struct {
    NSMutableData *inputReport;  // retained until the device cancel handler runs
    HIDGamepadRumbleHandler rumbleHandler;
} HIDGamepadCallbackContext;

static IOReturn getReportCallback(void *refcon, int type, uint32_t reportID,
                                  uint8_t *report, CFIndex length) {
    HIDGamepadCallbackContext *context = (HIDGamepadCallbackContext *)refcon;
    IOReturn result = kIOReturnSuccess;
    if (!report || length < 0) {
        result = kIOReturnBadArgument;
    } else {
        memset(report, 0, (size_t)length);
    }
    if (result == kIOReturnSuccess && type == kIOHIDReportTypeInput && reportID == 1) {
        @synchronized (context->inputReport) {
            CFIndex size = MIN(length, (CFIndex)context->inputReport.length);
            memcpy(report, context->inputReport.bytes, (size_t)size);
        }
    } else if (result == kIOReturnSuccess) {
        // Match x360w's GET response byte-for-byte: zero-fill the requested
        // buffer, echo the report ID, and provide its canned firmware/pairing
        // fields. In particular, ID 0x0b is not in our USB descriptor and gets
        // the same generic successful response as x360w.
        if (length > 0) report[0] = (uint8_t)reportID;
        if (type == kIOHIDReportTypeFeature && reportID == 0x09 && length >= 7) {
            const uint8_t address[] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
            memcpy(report + 1, address, sizeof(address));
        } else if (type == kIOHIDReportTypeFeature && reportID == 0x20 && length >= 4) {
            report[1] = report[2] = report[3] = 0x30;
        }
    }

    char bytes[3 * 16 + 1] = {};
    if (report && length > 0) {
        CFIndex count = MIN(length, 16);
        for (CFIndex i = 0; i < count; ++i) {
            snprintf(bytes + i * 3, sizeof(bytes) - (size_t)i * 3, "%02x ", report[i]);
        }
    }
    NSLog(@"[HIDGamepad] GET type=%d id=0x%02x len=%ld data=[%s] result=0x%x",
          type, reportID, (long)length, bytes, result);
    return result;
}

static IOReturn setReportCallback(void *refcon, int type, uint32_t reportID,
                                  uint8_t *report, CFIndex length) {
    HIDGamepadCallbackContext *context = (HIDGamepadCallbackContext *)refcon;
    // x360w accepts every SET report; keep that behavior for this A/B test and
    // log the exact handshake requests GameController sends.
    char bytes[3 * 8 + 1] = {};
    if (report && length > 0) {
        CFIndex count = MIN(length, 8);
        for (CFIndex i = 0; i < count; ++i) {
            snprintf(bytes + i * 3, sizeof(bytes) - (size_t)i * 3, "%02x ", report[i]);
        }
    }
    NSLog(@"[HIDGamepad] SET type=%d id=0x%02x len=%ld data=[%s] result=0x%x",
          type, reportID, (long)length, bytes, (unsigned)kIOReturnSuccess);
    if (type == kIOHIDReportTypeOutput && reportID == 2 && report && length >= 5 && context->rumbleHandler) {
        // DualSense USB output report: byte 3 is weak/right motor, byte 4 is
        // strong/left motor, matching x360w's rumble extraction.
        context->rumbleHandler(report[4], report[3]);
    }
    return kIOReturnSuccess;
}

static NSDictionary *deviceProperties(int index) {
    return @{
        @kIOHIDVendorIDKey:       @(0x054c),
        @kIOHIDProductIDKey:      @(0x0ce6),
        @kIOHIDVersionNumberKey:  @(0x0100),
        // Match x360w's native DualSense identity so consumers which classify
        // controllers by their HID properties see the same profile.
        @kIOHIDManufacturerKey:   @"Sony Interactive Entertainment",
        @kIOHIDProductKey:        @"DualSense Wireless Controller",
        @kIOHIDSerialNumberKey:   [NSString stringWithFormat:@"X360W-D%d", index + 1],
        @kIOHIDTransportKey:      @"USB",
        @kIOHIDPrimaryUsagePageKey: @(0x01),
        @kIOHIDPrimaryUsageKey:     @(0x05),
        @kIOHIDLocationIDKey:       @(0x360000 + index),
        @kIOHIDReportDescriptorKey: [NSData dataWithBytes:kDualSenseReportDescriptor
                                                   length:sizeof(kDualSenseReportDescriptor)],
    };
}

@implementation HIDGamepad

+ (BOOL)isAvailable {
    // Probe the same identity/descriptor as the real device, without publishing
    // a short-lived controller to applications or racing driver setup requests.
    IOHIDUserDeviceRef device = IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault, (__bridge CFDictionaryRef)deviceProperties(0),
        IOHIDUserDeviceOptionsCreateOnActivate);
    if (!device) return NO;
    CFRelease(device);
    return YES;
}

- (instancetype)initWithIndex:(int)index {
    return [self initWithIndex:index rumbleHandler:nil];
}

- (instancetype)initWithIndex:(int)index rumbleHandler:(HIDGamepadRumbleHandler)handler {
    self = [super init];
    if (self) {
        _gamepadIndex = index;
        self.rumbleHandler = handler;
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
    [super dealloc];
}

- (BOOL)createDevice {
    @synchronized (self) {
        if (_hidDevice) return YES;

        // Defer publication until the get/set-report handlers are installed.
        _hidDevice = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault, (__bridge CFDictionaryRef)deviceProperties(_gamepadIndex),
            IOHIDUserDeviceOptionsCreateOnActivate);
        if (!_hidDevice) {
            NSLog(@"[HIDGamepad] Cannot create DualSense %d; check virtual HID signing entitlement", _gamepadIndex);
            return NO;
        }

        NSString *label = [NSString stringWithFormat:@"com.lumina.hid.gamepad.%d", _gamepadIndex];
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        _hidQueue = dispatch_queue_create([label UTF8String], attr);
        HIDGamepadReport neutral = dualSenseReport(0, 0, 0, 0, 0, 0, 0);
        _sequence = 0;
        _timestamp = 1000;
        dualSenseSetTimestamp(&neutral, _timestamp);
        _inputReport = [[NSMutableData alloc] initWithBytes:&neutral length:sizeof(neutral)];

        HIDRegisterReportCallback registerGet = (HIDRegisterReportCallback)
            dlsym(RTLD_DEFAULT, "IOHIDUserDeviceRegisterGetReportCallback");
        HIDRegisterReportCallback registerSet = (HIDRegisterReportCallback)
            dlsym(RTLD_DEFAULT, "IOHIDUserDeviceRegisterSetReportCallback");
        if (!registerGet || !registerSet) {
            NSLog(@"[HIDGamepad] Legacy report callback API is unavailable");
            CFRelease(_hidDevice);
            _hidDevice = NULL;
            dispatch_release(_hidQueue);
            _hidQueue = nil;
            [_inputReport release];
            _inputReport = nil;
            return NO;
        }

        HIDGamepadCallbackContext *context = calloc(1, sizeof(*context));
        context->inputReport = [_inputReport retain];
        context->rumbleHandler = self.rumbleHandler ? Block_copy(self.rumbleHandler) : nil;
        // Match x360w's setup order: queue, cancel handler, report callbacks,
        // then activate the virtual HID device.
        IOHIDUserDeviceSetDispatchQueue(_hidDevice, _hidQueue);
        IOHIDUserDeviceRef device = _hidDevice;
        IOHIDUserDeviceSetCancelHandler(device, ^{
            if (context->rumbleHandler) Block_release(context->rumbleHandler);
            [context->inputReport release];
            free(context);
            CFRelease(device);
        });
        registerGet(_hidDevice, getReportCallback, context);
        registerSet(_hidDevice, setReportCallback, context);
        IOHIDUserDeviceActivate(_hidDevice);
        _isConnected = YES;

        IOReturn result = IOHIDUserDeviceHandleReportWithTimeStamp(
            _hidDevice, mach_absolute_time(), (const uint8_t *)&neutral, sizeof(neutral));
        if (result != kIOReturnSuccess) {
            NSLog(@"[HIDGamepad] Initial DualSense report failed for %d (0x%x)", _gamepadIndex, result);
            [self disconnect];
            return NO;
        }
        // HID publication alone is not proof that GameController has attached.
        NSLog(@"[HIDGamepad] DualSense-compatible HID device %d published", _gamepadIndex);
        return YES;
    }
}

- (void)updateState:(uint32_t)buttons
         leftStickX:(int16_t)lsX
         leftStickY:(int16_t)lsY
        rightStickX:(int16_t)rsX
        rightStickY:(int16_t)rsY
        leftTrigger:(uint8_t)lt
       rightTrigger:(uint8_t)rt {
    @synchronized (self) {
        if (!_isConnected || !_hidDevice) return;
        HIDGamepadReport report = dualSenseReport(buttons, lsX, lsY, rsX, rsY, lt, rt);
        report.sequence = ++_sequence;
        _timestamp += 1000;  // Same monotonically increasing tick as x360w.
        dualSenseSetTimestamp(&report, _timestamp);
        @synchronized (_inputReport) {
            memcpy([_inputReport mutableBytes], &report, sizeof(report));
        }
        // Serialize cache updates and sends, including rapid press/release.
        IOReturn result = IOHIDUserDeviceHandleReportWithTimeStamp(
            _hidDevice, mach_absolute_time(), (const uint8_t *)&report, sizeof(report));
        if (self.diagnosticReportLogging) {
            char bytes[3 * sizeof(report) + 1] = {};
            const uint8_t *raw = (const uint8_t *)&report;
            for (size_t i = 0; i < sizeof(report); ++i) {
                snprintf(bytes + i * 3, sizeof(bytes) - i * 3, "%02x ", raw[i]);
            }
            NSLog(@"[HIDGamepad] INPUT seq=%u timestamp=%u result=0x%x report=[%s]",
                  report.sequence, _timestamp, result, bytes);
        }
        if (result != kIOReturnSuccess) {
            NSLog(@"[HIDGamepad] Report failed for gamepad %d (0x%x)", _gamepadIndex, result);
        }
    }
}

- (void)disconnect {
    @synchronized (self) {
        if (!_hidDevice) return;
        _isConnected = NO;
        IOHIDUserDeviceRef device = _hidDevice;
        dispatch_queue_t queue = _hidQueue;
        _hidDevice = NULL;
        _hidQueue = nil;
        // Never wait on the HID callback queue. Cancellation owns the device
        // until callbacks finish, and their captured report cache stays alive.
        IOHIDUserDeviceCancel(device);
        dispatch_release(queue);
        [_inputReport release];
        _inputReport = nil;
        NSLog(@"[HIDGamepad] Gamepad %d disconnected", _gamepadIndex);
    }
}

@end
