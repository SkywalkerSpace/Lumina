/**
 * @file src/platform/macos/hid_gamepad.h
 * @brief Virtual HID gamepad via IOHIDUserDevice for macOS.
 * @details Publishes a USB DualSense-compatible gamepad for native GameController
 *          and HID clients. Requires the restricted virtual HID entitlement.
 */
#pragma once

#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDUserDevice.h>

#include "dualsense_gamepad.h"

@interface HIDGamepad : NSObject {
    NSMutableData *_inputReport;
    uint8_t _sequence;
}

@property (nonatomic, assign) int gamepadIndex;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) IOHIDUserDeviceRef hidDevice;
@property (nonatomic, strong) dispatch_queue_t hidQueue;

/**
 * Probes whether IOHIDUserDevice virtual gamepads can be created.
 * Returns NO when device creation is denied (e.g. missing HID entitlement).
 */
+ (BOOL)isAvailable;

- (instancetype)initWithIndex:(int)index;

/**
 * Creates the IOHIDUserDevice and sends an initial neutral-state report.
 * @return YES on success, NO on failure.
 */
- (BOOL)createDevice;

/**
 * Maps Sunshine's gamepad state to an HID report and sends it.
 * @param buttons  Sunshine's 32-bit buttonFlags (including HOME/TOUCHPAD/MISC)
 * @param lsX      Left stick X (-32768..32767)
 * @param lsY      Left stick Y (-32768..32767)
 * @param rsX      Right stick X (-32768..32767)
 * @param rsY      Right stick Y (-32768..32767)
 * @param lt       Left trigger (0..255)
 * @param rt       Right trigger (0..255)
 */
- (void)updateState:(uint32_t)buttons
         leftStickX:(int16_t)lsX
         leftStickY:(int16_t)lsY
        rightStickX:(int16_t)rsX
        rightStickY:(int16_t)rsY
        leftTrigger:(uint8_t)lt
       rightTrigger:(uint8_t)rt;

/**
 * Destroys the IOHIDUserDevice and cleans up resources.
 */
- (void)disconnect;

@end
