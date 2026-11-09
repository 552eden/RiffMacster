// Prints the whammy (Slider) and tilt (Dial) values that apps see on the
// RiffMacster virtual guitar. Build: swiftc -O tools/axes.swift -o build/axes
import Foundation
import IOKit.hid

let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x0E6F, kIOHIDProductIDKey: 0x0249, kIOHIDTransportKey: "Virtual"] as CFDictionary)
IOHIDManagerSetInputValueMatchingMultiple(m, [
    [kIOHIDElementUsagePageKey: 1, kIOHIDElementUsageKey: 0x36],
    [kIOHIDElementUsagePageKey: 1, kIOHIDElementUsageKey: 0x37],
] as CFArray)
IOHIDManagerRegisterDeviceMatchingCallback(m, { _, _, _, d in
    print("found:", IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) ?? "?")
}, nil)
IOHIDManagerRegisterInputValueCallback(m, { _, _, _, v in
    let usage = IOHIDElementGetUsage(IOHIDValueGetElement(v))
    print(usage == 0x36 ? "whammy" : "tilt  ", IOHIDValueGetIntegerValue(v))
}, nil)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(m, 0)
print("move the whammy / tilt the guitar (Ctrl-C to quit)…")
CFRunLoopRun()
