/*
 * Xbox Bluetooth-compatible HID input, implemented from the wire layout
 * consumed by SDL's HIDAPI Xbox One Bluetooth driver (SDL_hidapi_xboxone.c).
 * Descriptor items below are authored locally from the USB HID usage tables.
 * No GIP/USB Xbox protocol, motion, haptics or Bluetooth radio is implemented.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

static const uint8_t kXboxReportDescriptor[] = {
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, // Generic Desktop / Game Pad
    0x85, 0x01,                         // Input report 1
    0x09, 0x01, 0xa1, 0x00,             // Physical pointer: four unsigned sticks
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35,
    0x15, 0x00, 0x27, 0xff, 0xff, 0x00, 0x00,
    0x75, 0x10, 0x95, 0x04, 0x81, 0x02, 0xc0,
    0x05, 0x02, 0x09, 0xc5,             // Simulation / Brake: left trigger
    0x15, 0x00, 0x26, 0xff, 0x03, 0x75, 0x0a, 0x95, 0x01, 0x81, 0x02,
    0x25, 0x00, 0x75, 0x06, 0x81, 0x03, // Six padding bits
    0x09, 0xc4,                         // Accelerator: right trigger
    0x26, 0xff, 0x03, 0x75, 0x0a, 0x81, 0x02,
    0x25, 0x00, 0x75, 0x06, 0x81, 0x03,
    0x05, 0x01, 0x09, 0x39,             // Hat: 1..8, null state 0
    0x15, 0x01, 0x25, 0x08, 0x35, 0x00, 0x46, 0x3b, 0x01,
    0x65, 0x14, 0x75, 0x04, 0x81, 0x42,
    0x65, 0x00, 0x35, 0x00, 0x45, 0x00, // Reset units and physical range
    0x15, 0x00, 0x25, 0x00, 0x81, 0x03, // Four padding bits
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0f,
    0x25, 0x01, 0x75, 0x01, 0x95, 0x0f, 0x81, 0x02, // Buttons 1..15
    0x25, 0x00, 0x95, 0x01, 0x81, 0x03, // One padding bit
    0x05, 0x0c, 0x0a, 0xb2, 0x00,       // Consumer / Record: Share
    0x25, 0x01, 0x81, 0x02, 0x25, 0x00, 0x75, 0x07, 0x81, 0x03,
    0x05, 0x01, 0x09, 0x80, 0xa1, 0x00,
    0x85, 0x02, 0x09, 0x85,             // Report 2: System Main Menu / Guide
    0x25, 0x01, 0x75, 0x01, 0x81, 0x02,
    0x25, 0x00, 0x75, 0x07, 0x81, 0x03, 0xc0,
    0x85, 0x03, 0x05, 0x0f, 0x09, 0x21, 0xa1, 0x02,
    0x09, 0x97, 0x25, 0x01, 0x75, 0x04, 0x91, 0x02, // Four actuator enable bits
    0x25, 0x00, 0x91, 0x03,             // Four padding bits
    0x09, 0x70, 0x25, 0x64, 0x75, 0x08, 0x95, 0x04, 0x91, 0x02,
    0x09, 0x50, 0x09, 0xa7, 0x09, 0x7c, // Duration, delay, loop count
    0x26, 0xff, 0x00, 0x95, 0x03, 0x91, 0x02, 0xc0,
    0xc0
};

typedef struct {
    uint8_t reportId;
    uint8_t sticks[8];
    uint8_t triggers[4];
    uint8_t hat;
    uint8_t buttons[2];
    uint8_t share;
} HIDXboxReport;

#if defined(__cplusplus)
static_assert(sizeof(HIDXboxReport) == 17, "Xbox Bluetooth input report size");
#else
_Static_assert(sizeof(HIDXboxReport) == 17, "Xbox Bluetooth input report size");
#endif

static inline void xboxWrite16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static inline uint16_t xboxStick(int16_t value, int invert) {
    int32_t axis = invert ? -(int32_t)value : value;
    if (axis > INT16_MAX) axis = INT16_MAX;
    return (uint16_t)(axis + 32768);
}

static inline HIDXboxReport xboxReport(uint32_t flags,
        int16_t lx, int16_t ly, int16_t rx, int16_t ry, uint8_t lt, uint8_t rt) {
    HIDXboxReport report;
    memset(&report, 0, sizeof(report));
    report.reportId = 1;
    xboxWrite16(report.sticks, xboxStick(lx, 0));
    xboxWrite16(report.sticks + 2, xboxStick(ly, 1));
    xboxWrite16(report.sticks + 4, xboxStick(rx, 0));
    xboxWrite16(report.sticks + 6, xboxStick(ry, 1));
    xboxWrite16(report.triggers, (uint16_t)((unsigned)lt * 1023 / 255));
    xboxWrite16(report.triggers + 2, (uint16_t)((unsigned)rt * 1023 / 255));
    int x = !!(flags & 0x0008) - !!(flags & 0x0004);
    int y = !!(flags & 0x0002) - !!(flags & 0x0001);
    static const uint8_t hats[] = {8, 1, 2, 7, 0, 3, 6, 5, 4};
    report.hat = hats[(y + 1) * 3 + x + 1];
    // Xbox Bluetooth uses sparse button usages, not consecutive ABXY/LB/RB bits.
    if (flags & 0x1000) report.buttons[0] |= 0x01; // A
    if (flags & 0x2000) report.buttons[0] |= 0x02; // B
    if (flags & 0x4000) report.buttons[0] |= 0x08; // X
    if (flags & 0x8000) report.buttons[0] |= 0x10; // Y
    if (flags & 0x0100) report.buttons[0] |= 0x40; // LB
    if (flags & 0x0200) report.buttons[0] |= 0x80; // RB
    if (flags & 0x0020) report.buttons[1] |= 0x04; // View
    if (flags & 0x0010) report.buttons[1] |= 0x08; // Menu
    if (flags & 0x0400) report.buttons[1] |= 0x10; // Guide (also report 2)
    if (flags & 0x0040) report.buttons[1] |= 0x20; // LS
    if (flags & 0x0080) report.buttons[1] |= 0x40; // RS
    if (flags & 0x100000) report.share = 1;       // Touchpad click -> Share
    return report;
}
