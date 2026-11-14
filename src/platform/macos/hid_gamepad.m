/**
 * @file src/platform/macos/hid_gamepad.m
 * @brief USB DualSense-compatible virtual gamepad via IOHIDUserDevice.
 * @details Requires com.apple.developer.hid.virtual.device in the executable's
 *          effective signing entitlements. No system security settings are changed.
 */
#import "hid_gamepad.h"
#import <mach/mach_time.h>

static NSDictionary *deviceProperties(int index) {
    return @{
        @kIOHIDVendorIDKey:       @(0x054c),
        @kIOHIDProductIDKey:      @(0x0ce6),
        @kIOHIDVersionNumberKey:  @(0x0100),
        @kIOHIDManufacturerKey:   @"Lumina",
        @kIOHIDProductKey:        @"Lumina DualSense Compatible",
        @kIOHIDSerialNumberKey:   [NSString stringWithFormat:@"LUMINA-DS-%d", index],
        @kIOHIDTransportKey:      @"USB",
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
    self = [super init];
    if (self) {
        _gamepadIndex = index;
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
        _inputReport = [[NSMutableData alloc] initWithBytes:&neutral length:sizeof(neutral)];

        // Capture the cache, not self: self -> device -> block -> self would leak.
        // The block retains the cache through asynchronous device cancellation.
        NSMutableData *cache = _inputReport;
        uint8_t index = (uint8_t)_gamepadIndex;
        IOHIDUserDeviceRegisterGetReportBlock(_hidDevice,
            ^IOReturn(IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex *length) {
                if (!report || !length || *length < 0) return kIOReturnBadArgument;
                if (type == kIOHIDReportTypeInput && reportID == 1) {
                    @synchronized (cache) {
                        CFIndex size = MIN(*length, (CFIndex)[cache length]);
                        memcpy(report, [cache bytes], (size_t)size);
                        *length = size;
                    }
                    return kIOReturnSuccess;
                }
                if (type == kIOHIDReportTypeFeature) {
                    uint8_t feature[64];
                    size_t size = dualSenseFeatureReport(reportID, feature, index);
                    if (!size) return kIOReturnUnsupported;
                    size = MIN(size, (size_t)*length);
                    memcpy(report, feature, size);
                    *length = (CFIndex)size;
                    return kIOReturnSuccess;
                }
                return kIOReturnUnsupported;
            });
        IOHIDUserDeviceRegisterSetReportBlock(_hidDevice,
            ^IOReturn(IOHIDReportType type, uint32_t reportID, const uint8_t *report, CFIndex length) {
                // Acknowledge driver setup, LED and rumble writes; no physical
                // actuator or feedback forwarding is implemented yet.
                (void)report;
                (void)length;
                if ((type == kIOHIDReportTypeOutput && reportID == 2) ||
                    (type == kIOHIDReportTypeFeature && dualSenseFeatureLength(reportID))) {
                    return kIOReturnSuccess;
                }
                return kIOReturnUnsupported;
            });
        IOHIDUserDeviceRef device = _hidDevice;
        IOHIDUserDeviceSetCancelHandler(device, ^{
            CFRelease(device);
        });
        IOHIDUserDeviceSetDispatchQueue(_hidDevice, _hidQueue);
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
        @synchronized (_inputReport) {
            memcpy([_inputReport mutableBytes], &report, sizeof(report));
        }
        // Serialize cache updates and sends, including rapid press/release.
        IOReturn result = IOHIDUserDeviceHandleReportWithTimeStamp(
            _hidDevice, mach_absolute_time(), (const uint8_t *)&report, sizeof(report));
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
