/* Xbox wire layout tests, independent of IOKit and signing permissions. */
#include "xbox_gamepad.h"
#include <assert.h>
#include <stdio.h>

static uint16_t read16(const uint8_t *bytes) {
    return (uint16_t)(bytes[0] | (uint16_t)bytes[1] << 8);
}

static void test_axes(void) {
    HIDXboxReport r = xboxReport(0, 0, 0, 0, 0, 0, 0);
    assert(sizeof(r) == 17 && r.reportId == 1);
    for (unsigned i = 0; i < 4; ++i) assert(read16(r.sticks + 2 * i) == 32768);
    assert(read16(r.triggers) == 0 && read16(r.triggers + 2) == 0);
    assert(r.hat == 0 && r.buttons[0] == 0 && r.buttons[1] == 0 && r.share == 0);
    r = xboxReport(0, INT16_MIN, INT16_MAX, INT16_MAX, INT16_MIN, 64, 255);
    assert(read16(r.sticks) == 0 && read16(r.sticks + 2) == 1);
    assert(read16(r.sticks + 4) == 65535 && read16(r.sticks + 6) == 65535);
    assert(read16(r.triggers) == 256 && read16(r.triggers + 2) == 1023);
    for (unsigned trigger = 0; trigger < 256; ++trigger) {
        r = xboxReport(0, 0, 0, 0, 0, (uint8_t)trigger, (uint8_t)trigger);
        assert(read16(r.triggers) == trigger * 1023 / 255);
        assert((r.triggers[1] & 0xfc) == 0 && (r.triggers[3] & 0xfc) == 0);
    }
}

static void test_buttons(void) {
    const uint32_t flags[] = {0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200,
                             0x0020, 0x0010, 0x0400, 0x0040, 0x0080};
    const unsigned bits[] = {0, 1, 3, 4, 6, 7, 10, 11, 12, 13, 14};
    for (unsigned i = 0; i < sizeof(flags) / sizeof(flags[0]); ++i) {
        HIDXboxReport r = xboxReport(flags[i], 0, 0, 0, 0, 0, 0);
        assert(read16(r.buttons) == (1u << bits[i]));
    }
    const uint32_t hats[] = {0, 1, 1 | 8, 8, 2 | 8, 2, 2 | 4, 4, 1 | 4};
    for (unsigned i = 0; i < 9; ++i) {
        HIDXboxReport r = xboxReport(hats[i], 0, 0, 0, 0, 0, 0);
        assert(r.hat == i);
    }
    HIDXboxReport r = xboxReport(1 | 2 | 4 | 8 | 0x100000, 0, 0, 0, 0, 0, 0);
    assert(r.hat == 0 && r.share == 1);
    r = xboxReport(UINT32_MAX, 0, 0, 0, 0, 0, 0);
    assert((read16(r.buttons) & 0x8324) == 0); // Unused usages and padding stay clear.
}

static void test_descriptor(void) {
    unsigned size = 0, count = 0, id = 0;
    unsigned input[256] = {0}, output[256] = {0}, feature[256] = {0};
    for (size_t i = 0; i < sizeof(kXboxReportDescriptor);) {
        uint8_t prefix = kXboxReportDescriptor[i++];
        unsigned length = prefix & 3;
        if (length == 3) length = 4;
        assert(i + length <= sizeof(kXboxReportDescriptor));
        unsigned value = 0;
        for (unsigned j = 0; j < length; ++j) value |= (unsigned)kXboxReportDescriptor[i++] << (8 * j);
        switch (prefix & 0xfc) {
            case 0x74: size = value; break;
            case 0x94: count = value; break;
            case 0x84: id = value; assert(id < 256); break;
            case 0x80: input[id] += size * count; break;
            case 0x90: output[id] += size * count; break;
            case 0xb0: feature[id] += size * count; break;
        }
    }
    assert(input[1] == (sizeof(HIDXboxReport) - 1) * 8);
    assert(input[2] == 8 && output[3] == 64);
    for (unsigned i = 0; i < 256; ++i) {
        if (i != 1 && i != 2) assert(input[i] == 0);
        if (i != 3) assert(output[i] == 0);
        assert(feature[i] == 0);
    }
}

int main(void) {
    test_axes();
    test_buttons();
    test_descriptor();
    puts("Xbox report and descriptor tests passed");
    return 0;
}
