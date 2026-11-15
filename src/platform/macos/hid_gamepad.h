/**
 * @file src/platform/macos/hid_gamepad.h
 * @brief Virtual HID gamepad via IOHIDUserDevice for macOS.
 * @details Publishes DualSense USB or Xbox Bluetooth wire profiles for native
 *          GameController and HID clients. Requires the virtual HID entitlement.
 */
#pragma once

#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDUserDevice.h>

#include "dualsense_gamepad.h"
#include "xbox_gamepad.h"

typedef NS_ENUM(NSUInteger, HIDGamepadProfile) {
    HIDGamepadProfileDualSense,
    HIDGamepadProfileXbox,
};

@interface HIDGamepad : NSObject {
    NSMutableData *_inputReport;
    uint8_t _sequence;
    BOOL _loggedInput;
}

@property (nonatomic, readonly) HIDGamepadProfile profile;
@property (nonatomic, readonly) NSString *profileName;

// Keep the existing DualSense default on macOS 15; prefer the Xbox Bluetooth
// wire profile on newer systems. This creates no actual Bluetooth connection.
+ (HIDGamepadProfile)defaultProfile;

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
- (instancetype)initWithIndex:(int)index profile:(HIDGamepadProfile)profile;

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
