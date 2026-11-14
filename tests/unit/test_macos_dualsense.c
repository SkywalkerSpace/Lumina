/* Standalone protocol tests; no HID entitlement or running controller needed.
 * Run: clang -std=c11 -Wall -Wextra -Werror -Isrc/platform/macos \
 *        tests/unit/test_macos_dualsense.c -o /tmp/lumina-dualsense-tests \
 *        && /tmp/lumina-dualsense-tests
 */
#include "dualsense_gamepad.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void test_neutral_and_axes(void) {
    HIDGamepadReport report = dualSenseReport(0, 0, 0, 0, 0, 0, 0);
    assert(sizeof(report) == 64);
    assert(report.reportId == 1);
    assert(report.leftStickX == 128 && report.leftStickY == 128);
    assert(report.rightStickX == 128 && report.rightStickY == 128);
    assert(report.leftTrigger == 0 && report.rightTrigger == 0);
    assert(report.buttons[0] == 8 && report.buttons[1] == 0 && report.buttons[2] == 0);
    assert(report.reserved[22] == 0x80 && report.reserved[26] == 0x80);

    report = dualSenseReport(0, INT16_MIN, INT16_MAX, INT16_MAX, INT16_MIN, 123, 255);
    assert(report.leftStickX == 0 && report.leftStickY == 0);
    assert(report.rightStickX == 255 && report.rightStickY == 255);
    assert(report.leftTrigger == 123 && report.rightTrigger == 255);
}

static void test_buttons_and_hat(void) {
    const uint32_t flags[] = {0x4000, 0x1000, 0x2000, 0x8000, 0x0100, 0x0200,
                              0x0020, 0x0010, 0x0040, 0x0080, 0x0400, 0x100000, 0x200000};
    const unsigned bytes[] = {0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2};
    const uint8_t bits[] = {0x10, 0x20, 0x40, 0x80, 1, 2, 0x10, 0x20, 0x40, 0x80, 1, 2, 4};
    for (unsigned i = 0; i < sizeof(flags) / sizeof(flags[0]); ++i) {
        HIDGamepadReport report = dualSenseReport(flags[i], 0, 0, 0, 0, 0, 0);
        uint8_t expected[3] = {8, 0, 0};
        expected[bytes[i]] |= bits[i];
        assert(memcmp(report.buttons, expected, sizeof(expected)) == 0);
    }
    const uint32_t directions[] = {1, 1 | 8, 8, 2 | 8, 2, 2 | 4, 4, 1 | 4, 0};
    for (unsigned i = 0; i < 9; ++i) {
        HIDGamepadReport report = dualSenseReport(directions[i], 0, 0, 0, 0, 0, 0);
        assert(report.buttons[0] == i);
    }
    HIDGamepadReport report = dualSenseReport(0, 0, 0, 0, 0, 1, 255);
    assert(report.buttons[1] == 0x08); // Digital threshold must not overwrite the analog value.
    assert(report.leftTrigger == 1 && report.rightTrigger == 255);
    report = dualSenseReport(1 | 2 | 4 | 8, 0, 0, 0, 0, 128, 127);
    assert(report.buttons[0] == 8); // Opposite directions cancel.
    assert(report.buttons[1] == 0x04);
}

/* Parse short HID items independently of the report serializer. */
static void test_descriptor(void) {
    unsigned size = 0, count = 0, id = 0;
    unsigned input[256] = {0}, output[256] = {0}, feature[256] = {0};
    assert(kDualSenseReportDescriptor[3] == 0x05); // Generic Desktop / Game Pad.
    for (size_t i = 0; i < sizeof(kDualSenseReportDescriptor);) {
        uint8_t prefix = kDualSenseReportDescriptor[i++];
        unsigned length = prefix & 3;
        if (length == 3) length = 4;
        assert(i + length <= sizeof(kDualSenseReportDescriptor));
        unsigned value = 0;
        for (unsigned j = 0; j < length; ++j) value |= (unsigned)kDualSenseReportDescriptor[i++] << (8 * j);
        switch (prefix & 0xfc) {
            case 0x74: size = value; break;
            case 0x94: count = value; break;
            case 0x84: id = value; assert(id < 256); break;
            case 0x80: input[id] += size * count; break;
            case 0x90: output[id] += size * count; break;
            case 0xb0: feature[id] += size * count; break;
        }
    }
    assert(input[1] == 63 * 8);
    assert(output[2] == 47 * 8);
    assert(feature[5] == 40 * 8);
    assert(feature[0x09] == 19 * 8);
    assert(feature[0x20] == 63 * 8);
    for (unsigned reportID = 0; reportID < 256; ++reportID) {
        size_t length = dualSenseFeatureLength(reportID);
        assert(feature[reportID] == (length ? (length - 1) * 8 : 0));
    }
}

static int16_t read_le16(const uint8_t *bytes) {
    return (int16_t)((uint16_t)bytes[0] | (uint16_t)bytes[1] << 8);
}

static void test_features(void) {
    uint8_t report[64], other[64];
    for (unsigned id = 0; id < 256; ++id) {
        size_t length = dualSenseFeatureReport(id, report, 0);
        assert(length == dualSenseFeatureLength(id));
        if (length) {
            assert(length <= sizeof(report));
            assert(report[0] == id);
        }
    }
    assert(dualSenseFeatureLength(0x100) == 0);
    assert(dualSenseFeatureReport(0x09, report, 0) == 20);
    assert(dualSenseFeatureReport(0x09, other, 15) == 20);
    assert((report[1] & 3) == 2); // Unicast, locally administered.
    assert(memcmp(report + 1, other + 1, 6) != 0); // Separate controller slots.
    assert(dualSenseFeatureReport(0x05, report, 0) == 41);
    const unsigned positive[] = {7, 11, 15, 23, 27, 31};
    for (unsigned i = 0; i < 6; ++i) {
        assert(read_le16(report + positive[i]) == 8192);
        assert(read_le16(report + positive[i] + 2) == -8192);
    }
    assert(read_le16(report + 19) == 1024 && read_le16(report + 21) == 1024);
}

int main(void) {
    test_neutral_and_axes();
    test_buttons_and_hat();
    test_descriptor();
    test_features();
    puts("DualSense report and descriptor tests passed");
    return 0;
}
