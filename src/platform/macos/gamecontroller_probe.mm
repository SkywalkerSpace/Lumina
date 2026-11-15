/**
 * @file gamecontroller_probe.mm
 * @brief Command-line diagnostic for native GameController enumeration.
 */
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import "hid_gamepad.h"

#include <iostream>
#include <cmath>

namespace args {
  static void pumpRunLoop(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
  }

  int gamecontroller_list() {
    @autoreleasepool {
      [GCController setShouldMonitorBackgroundEvents:YES];

      // Allow GameController's asynchronous discovery to settle before taking
      // the snapshot. No virtual device is created by this command.
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

      NSArray<GCController *> *controllers = [GCController controllers];
      std::cout << "GameController controllers: " << controllers.count << std::endl;
      for (NSUInteger i = 0; i < controllers.count; ++i) {
        GCController *controller = controllers[i];
        NSString *vendor = controller.vendorName ?: @"(unknown)";
        NSString *category = controller.productCategory ?: @"(unknown)";
        NSString *profile = controller.extendedGamepad
            ? NSStringFromClass([controller.extendedGamepad class])
            : (controller.microGamepad ? NSStringFromClass([controller.microGamepad class]) : @"(none)");
        std::cout << "[" << i << "] vendor=" << vendor.UTF8String
                  << " productCategory=" << category.UTF8String
                  << " profile=" << profile.UTF8String
                  << " attached=" << (controller.isAttachedToDevice ? "yes" : "no")
                  << " playerIndex=" << controller.playerIndex << std::endl;
      }

      if (controllers.count == 0) {
        std::cout << "No controller is currently visible to GameController." << std::endl;
        return 2;
      }
      return 0;
    }
  }

  int gamecontroller_probe() {
    @autoreleasepool {
      [GCController setShouldMonitorBackgroundEvents:YES];
      __block unsigned eventCount = 0;
      GCController *target = nil;
      NSArray<GCController *> *previousControllers = [[GCController controllers] copy];
      id connectObserver = [[NSNotificationCenter defaultCenter]
          addObserverForName:GCControllerDidConnectNotification object:nil queue:nil
          usingBlock:^(NSNotification *notification) {
            GCController *controller = notification.object;
            NSLog(@"[GCProbe] connect vendor=%@ category=%@ attached=%d",
                  controller.vendorName, controller.productCategory, controller.isAttachedToDevice);
          }];
      id disconnectObserver = [[NSNotificationCenter defaultCenter]
          addObserverForName:GCControllerDidDisconnectNotification object:nil queue:nil
          usingBlock:^(NSNotification *notification) {
            GCController *controller = notification.object;
            NSLog(@"[GCProbe] disconnect vendor=%@ category=%@",
                  controller.vendorName, controller.productCategory);
          }];

      HIDGamepad *device = [[HIDGamepad alloc] initWithIndex:0];
      device.diagnosticReportLogging = YES;
      if (![device createDevice]) {
        [[NSNotificationCenter defaultCenter] removeObserver:connectObserver];
        [[NSNotificationCenter defaultCenter] removeObserver:disconnectObserver];
        [previousControllers release];
        [device release];
        return 1;
      }

      // Wait for GameController discovery, then watch the matching native
      // profile while sending a changing report every 100 ms (x360w cadence).
      for (unsigned i = 0; i < 20 && !target; ++i) {
        pumpRunLoop(0.1);
        for (GCController *controller in [GCController controllers]) {
          if (![previousControllers containsObject:controller] &&
              [controller.productCategory isEqualToString:@"DualSense"] && controller.extendedGamepad) {
            target = [controller retain];
            target.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
              (void)gamepad;
              (void)element;
              ++eventCount;
            };
            break;
          }
        }
      }

      std::cout << "Probe controller found: " << (target ? "yes" : "no")
                << ", attached=" << (target.isAttachedToDevice ? "yes" : "no") << std::endl;
      bool foundTarget = target != nil;
      for (unsigned frame = 0; frame < 100; ++frame) {
        double angle = frame * 0.21;
        static const uint32_t dpadFlags[] = {
          0x0001, 0x0009, 0x0008, 0x000a, 0x0002, 0x0006, 0x0004, 0x0005, 0x0000,
        };
        uint32_t buttons = (frame / 25 % 2 ? 0x1000 : 0) | dpadFlags[(frame / 12) % 9];
        [device updateState:buttons
                 leftStickX:(int16_t)(30000 * std::cos(angle))
                 leftStickY:(int16_t)(-30000 * std::sin(angle))
                rightStickX:0
                rightStickY:0
                leftTrigger:(uint8_t)frame
               rightTrigger:0];
        pumpRunLoop(0.1);
        if (frame % 10 == 9) {
          std::cout << "frame=" << frame + 1
                    << " attached=" << (target.isAttachedToDevice ? "yes" : "no")
                    << " GameController events=" << eventCount << std::endl;
        }
      }

      if (target) {
        target.extendedGamepad.valueChangedHandler = nil;
        [target release];
      }
      [device disconnect];
      [device release];
      [[NSNotificationCenter defaultCenter] removeObserver:connectObserver];
      [[NSNotificationCenter defaultCenter] removeObserver:disconnectObserver];
      [previousControllers release];
      return foundTarget && eventCount ? 0 : 2;
    }
  }
}  // namespace args
