/*
 * DualSense USB protocol, adapted from MacOSReconfigureController commit
 * 98fa996859030065582003b27d7cb0156b22a534. Motion, touch, audio, haptics and
 * adaptive triggers are not emulated.
 *
 * Descriptor: https://github.com/zeromiyi/x360w/blob/main/src/ds_desc.h
 * MIT License
 * Copyright (c) 2026 古董修复师
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

static const uint8_t kDualSenseReportDescriptor[] = {
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x09, 0x32, 0x09, 0x35, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF,
    0x00, 0x75, 0x08, 0x95, 0x06, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x20,
    0x95, 0x01, 0x81, 0x02, 0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
    0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81,
    0x42, 0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0F, 0x15, 0x00, 0x25,
    0x01, 0x75, 0x01, 0x95, 0x0F, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x21,
    0x95, 0x0D, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x22, 0x15, 0x00, 0x26,
    0xFF, 0x00, 0x75, 0x08, 0x95, 0x34, 0x81, 0x02, 0x85, 0x02, 0x09, 0x23,
    0x95, 0x2F, 0x91, 0x02, 0x85, 0x05, 0x09, 0x33, 0x95, 0x28, 0xB1, 0x02,
    0x85, 0x08, 0x09, 0x34, 0x95, 0x2F, 0xB1, 0x02, 0x85, 0x09, 0x09, 0x24,
    0x95, 0x13, 0xB1, 0x02, 0x85, 0x0A, 0x09, 0x25, 0x95, 0x1A, 0xB1, 0x02,
    0x85, 0x20, 0x09, 0x26, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x21, 0x09, 0x27,
    0x95, 0x04, 0xB1, 0x02, 0x85, 0x22, 0x09, 0x40, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0x80, 0x09, 0x28, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x81, 0x09, 0x29,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0x82, 0x09, 0x2A, 0x95, 0x09, 0xB1, 0x02,
    0x85, 0x83, 0x09, 0x2B, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x84, 0x09, 0x2C,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0x85, 0x09, 0x2D, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0xA0, 0x09, 0x2E, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xE0, 0x09, 0x2F,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0xF0, 0x09, 0x30, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0xF1, 0x09, 0x31, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xF2, 0x09, 0x32,
    0x95, 0x0F, 0xB1, 0x02, 0x85, 0xF4, 0x09, 0x35, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0xF5, 0x09, 0x36, 0x95, 0x03, 0xB1, 0x02, 0xC0
};

/* All fields are bytes: the layout is independent of host endianness/alignment. */
typedef struct {
    uint8_t reportId;
    uint8_t leftStickX, leftStickY, rightStickX, rightStickY;
    uint8_t leftTrigger, rightTrigger;
    uint8_t sequence;
    uint8_t buttons[3];
    uint8_t reserved[53];
} HIDGamepadReport;

#if defined(__cplusplus)
static_assert(sizeof(HIDGamepadReport) == 64, "DualSense USB input report size");
#else
_Static_assert(sizeof(HIDGamepadReport) == 64, "DualSense USB input report size");
#endif

/* Sunshine uses signed sticks with positive Y pointing up; USB HID Y points down.
 * Widen before negating so INT16_MIN does not overflow. */
static inline uint8_t dualSenseStick(int16_t value, int invert) {
    int32_t axis = invert ? -(int32_t)value : value;
    if (axis > INT16_MAX) axis = INT16_MAX;
    return (uint8_t)((axis + 32768) >> 8);
}

static inline HIDGamepadReport dualSenseReport(uint32_t flags,
        int16_t lx, int16_t ly, int16_t rx, int16_t ry, uint8_t lt, uint8_t rt) {
    HIDGamepadReport report;
    memset(&report, 0, sizeof(report));
    report.reportId = 1;
    report.leftStickX = dualSenseStick(lx, 0);
    report.leftStickY = dualSenseStick(ly, 1);
    report.rightStickX = dualSenseStick(rx, 0);
    report.rightStickY = dualSenseStick(ry, 1);
    report.leftTrigger = lt;
    report.rightTrigger = rt;
    int x = !!(flags & 0x0008) - !!(flags & 0x0004);
    int y = !!(flags & 0x0002) - !!(flags & 0x0001);
    static const uint8_t hats[] = {7, 0, 1, 6, 8, 2, 5, 4, 3};
    report.buttons[0] = hats[(y + 1) * 3 + x + 1];
    if (flags & 0x4000) report.buttons[0] |= 0x10; // X -> Square
    if (flags & 0x1000) report.buttons[0] |= 0x20; // A -> Cross
    if (flags & 0x2000) report.buttons[0] |= 0x40; // B -> Circle
    if (flags & 0x8000) report.buttons[0] |= 0x80; // Y -> Triangle
    if (flags & 0x0100) report.buttons[1] |= 0x01; // L1
    if (flags & 0x0200) report.buttons[1] |= 0x02; // R1
    if (lt > 127)      report.buttons[1] |= 0x04; // L2 digital
    if (rt > 127)      report.buttons[1] |= 0x08; // R2 digital
    if (flags & 0x0020) report.buttons[1] |= 0x10; // Back -> Create
    if (flags & 0x0010) report.buttons[1] |= 0x20; // Start -> Options
    if (flags & 0x0040) report.buttons[1] |= 0x40; // L3
    if (flags & 0x0080) report.buttons[1] |= 0x80; // R3
    if (flags & 0x0400)   report.buttons[2] |= 0x01; // PS
    if (flags & 0x100000) report.buttons[2] |= 0x02; // Touchpad click
    if (flags & 0x200000) report.buttons[2] |= 0x04; // Microphone/misc
    report.reserved[22] = 0x80; // byte 33: inactive touch contact
    report.reserved[26] = 0x80; // byte 37: inactive touch contact
    return report;
}

/* Lengths include the report-ID byte (as do IOHID get-report buffers). */
static inline size_t dualSenseFeatureLength(uint32_t id) {
    switch (id) {
        case 0x05: return 41;
        case 0x08: return 48;
        case 0x09: return 20;
        case 0x0a: return 27;
        case 0x21: return 5;
        case 0x82: return 10;
        case 0x85: return 3;
        case 0xa0: return 2;
        case 0xf2: return 16;
        case 0xf5: return 4;
        case 0x20: case 0x22: case 0x80: case 0x81: case 0x83: case 0x84:
        case 0xe0: case 0xf0: case 0xf1: case 0xf4: return 64;
        default: return 0;
    }
}

static inline size_t dualSenseFeatureReport(uint32_t id, uint8_t report[64], uint8_t index) {
    size_t length = dualSenseFeatureLength(id);
    if (!length) return 0;
    memset(report, 0, 64);
    report[0] = (uint8_t)id;
    if (id == 0x09) {
        /* Stable locally administered address, unique to each of our 16 slots. */
        const uint8_t address[] = {0x02, 0x4c, 0x55, 0x4d, 0x00, index};
        memcpy(report + 1, address, sizeof(address));
    } else if (id == 0x05) {
        const unsigned positive[] = {7, 11, 15, 23, 27, 31};
        const unsigned negative[] = {9, 13, 17, 25, 29, 33};
        for (unsigned i = 0; i < 6; ++i) {
            report[positive[i] + 1] = 0x20; // +8192, little endian
            report[negative[i] + 1] = 0xe0; // -8192
        }
        report[20] = report[22] = 0x04; // gyro speed +/- = 1024
    }
    return length;
}
