/**
 * @file src/platform/macos/hid_gamepad.m
 * @brief DualSense USB / Xbox Bluetooth wire profiles via IOHIDUserDevice.
 * @details Requires com.apple.developer.hid.virtual.device in the executable's
 *          effective signing entitlements. No system security settings are changed.
 */
#import "hid_gamepad.h"
#import <mach/mach_time.h>

static NSDictionary *deviceProperties(int index, HIDGamepadProfile profile) {
    BOOL xbox = profile == HIDGamepadProfileXbox;
    return @{
        @kIOHIDVendorIDKey:       @(xbox ? 0x045e : 0x054c),
        // 0x02FD identifies the Xbox One S Bluetooth controller (Model 1708),
        // matching this Bluetooth report descriptor. 0x0B13 is Xbox Series
        // and uses a different HID protocol.
        @kIOHIDProductIDKey:      @(xbox ? 0x02fd : 0x0ce6),
        @kIOHIDVersionNumberKey:  @(xbox ? 0 : 0x0100),
        @kIOHIDManufacturerKey:   @"Lumina",
        @kIOHIDProductKey:        xbox ? @"Lumina Xbox Compatible" : @"Lumina DualSense Compatible",
        @kIOHIDSerialNumberKey:   [NSString stringWithFormat:@"LUMINA-%@-%d", xbox ? @"XB" : @"DS", index],
        // A nonzero, distinct location also avoids collisions in HID clients
        // (including Chromium versions that key devices by LocationID).
        @kIOHIDLocationIDKey:     @(0x4c550000 + index),
        @kIOHIDPrimaryUsagePageKey: @1,
        @kIOHIDPrimaryUsageKey:   @5,
        @kIOHIDDeviceUsagePairsKey: @[@{
            @kIOHIDDeviceUsagePageKey: @1, @kIOHIDDeviceUsageKey: @5,
        }],
        @kIOHIDTransportKey:      xbox ? @"Bluetooth" : @"USB",
        @kIOHIDMaxInputReportSizeKey: @(xbox ? sizeof(HIDXboxReport) : sizeof(HIDGamepadReport)),
        @kIOHIDMaxOutputReportSizeKey: @(xbox ? 9 : 48),
        @kIOHIDReportDescriptorKey: xbox
            ? [NSData dataWithBytes:kXboxReportDescriptor length:sizeof(kXboxReportDescriptor)]
            : [NSData dataWithBytes:kDualSenseReportDescriptor length:sizeof(kDualSenseReportDescriptor)],
    };
}

static size_t buildInputReport(HIDGamepadProfile profile, uint8_t sequence,
        uint32_t buttons, int16_t lx, int16_t ly, int16_t rx, int16_t ry,
        uint8_t lt, uint8_t rt, uint8_t bytes[64]) {
    if (profile == HIDGamepadProfileXbox) {
        HIDXboxReport report = xboxReport(buttons, lx, ly, rx, ry, lt, rt);
        memcpy(bytes, &report, sizeof(report));
        return sizeof(report);
    }
    HIDGamepadReport report = dualSenseReport(buttons, lx, ly, rx, ry, lt, rt);
    report.sequence = sequence;
    memcpy(bytes, &report, sizeof(report));
    return sizeof(report);
}

@implementation HIDGamepad

+ (HIDGamepadProfile)defaultProfile {
    if (@available(macOS 27.0, *)) return HIDGamepadProfileXbox;
    return HIDGamepadProfileDualSense;
}

- (NSString *)profileName {
    return _profile == HIDGamepadProfileXbox ? @"Xbox Bluetooth-compatible" : @"USB DualSense-compatible";
}

+ (BOOL)isAvailable {
    // This probes creation permission, not native discovery/input delivery.
    IOHIDUserDeviceRef device = IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault, (__bridge CFDictionaryRef)deviceProperties(0, [self defaultProfile]),
        IOHIDUserDeviceOptionsCreateOnActivate);
    if (!device) return NO;
    CFRelease(device);
    return YES;
}

- (instancetype)initWithIndex:(int)index {
    return [self initWithIndex:index profile:[HIDGamepad defaultProfile]];
}

- (instancetype)initWithIndex:(int)index profile:(HIDGamepadProfile)profile {
    self = [super init];
    if (self) {
        _gamepadIndex = index;
        _profile = profile;
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
            kCFAllocatorDefault, (__bridge CFDictionaryRef)deviceProperties(_gamepadIndex, _profile),
            IOHIDUserDeviceOptionsCreateOnActivate);
        if (!_hidDevice) {
            NSLog(@"[HIDGamepad] Cannot create %@ %d; check virtual HID signing entitlement", self.profileName, _gamepadIndex);
            return NO;
        }

        NSString *label = [NSString stringWithFormat:@"com.lumina.hid.gamepad.%d", _gamepadIndex];
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        _hidQueue = dispatch_queue_create([label UTF8String], attr);
        uint8_t neutral[64];
        _sequence = 0;
        _loggedInput = NO;
        size_t neutralLength = buildInputReport(_profile, 0, 0, 0, 0, 0, 0, 0, 0, neutral);
        _inputReport = [[NSMutableData alloc] initWithBytes:neutral length:neutralLength];

        // Capture the cache, not self: self -> device -> block -> self would leak.
        // The block retains the cache through asynchronous device cancellation.
        NSMutableData *cache = _inputReport;
        uint8_t index = (uint8_t)_gamepadIndex;
        BOOL xbox = _profile == HIDGamepadProfileXbox;
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
                if (xbox && type == kIOHIDReportTypeInput && reportID == 2) {
                    if (*length < 2) return kIOReturnNoSpace;
                    @synchronized (cache) {
                        const HIDXboxReport *state = [cache bytes];
                        report[0] = 2;
                        report[1] = !!(state->buttons[1] & 0x10);
                    }
                    *length = 2;
                    return kIOReturnSuccess;
                }
                if (!xbox && type == kIOHIDReportTypeFeature) {
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
                // Acknowledge declared outputs; no physical actuator is emulated.
                (void)report;
                (void)length;
                if (type == kIOHIDReportTypeOutput && reportID == (xbox ? 3 : 2)) {
                    return kIOReturnSuccess;
                }
                if (!xbox && type == kIOHIDReportTypeFeature && dualSenseFeatureLength(reportID)) {
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
            _hidDevice, mach_absolute_time(), neutral, (CFIndex)neutralLength);
        if (result != kIOReturnSuccess) {
            NSLog(@"[HIDGamepad] Initial %@ report failed for %d (0x%x)", self.profileName, _gamepadIndex, result);
            [self disconnect];
            return NO;
        }
        // HID publication alone is not proof that GameController has attached.
        NSLog(@"[HIDGamepad] %@ HID device %d published; native input delivery requires verification", self.profileName, _gamepadIndex);
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
        uint8_t report[64];
        size_t length = buildInputReport(_profile, ++_sequence, buttons, lsX, lsY, rsX, rsY, lt, rt, report);
        @synchronized (_inputReport) {
            memcpy([_inputReport mutableBytes], report, length);
        }
        IOReturn result = IOHIDUserDeviceHandleReportWithTimeStamp(
            _hidDevice, mach_absolute_time(), report, (CFIndex)length);
        if (result != kIOReturnSuccess) {
            NSLog(@"[HIDGamepad] Report failed for gamepad %d (0x%x)", _gamepadIndex, result);
        } else if (!_loggedInput && (buttons || lsX || lsY || rsX || rsY || lt || rt)) {
            _loggedInput = YES;
            NSLog(@"[HIDGamepad] First non-neutral %@ input submitted for gamepad %d (%zu bytes)",
                  self.profileName, _gamepadIndex, length);
        }
        if (_profile == HIDGamepadProfileXbox) {
            // Apple's Xbox profile reads Home from System Main Menu report 2;
            // HIDAPI consumers can also read it from button 13 in report 1.
            const uint8_t guide[] = {2, !!(buttons & 0x0400)};
            result = IOHIDUserDeviceHandleReportWithTimeStamp(
                _hidDevice, mach_absolute_time(), guide, sizeof(guide));
            if (result != kIOReturnSuccess) {
                NSLog(@"[HIDGamepad] Guide report failed for gamepad %d (0x%x)", _gamepadIndex, result);
            }
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
