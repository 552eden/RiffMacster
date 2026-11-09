// Latency probe. Build: swiftc -O tools/latency.swift -o build/latency
// usage: build/latency <Virtual|USB> <seconds> [buttons]
//   Virtual = through RiffMacster; USB = real guitar read directly (stop RiffMacster first).
//   buttons = only count reports where frets, strum or buttons changed (press/release).
//
// For each input report: delay = now - report timestamp. The timestamp is the kernel's
// arrival time of the original USB report, and RiffMacster forwards that same timestamp,
// so this is the full path a game-side reader sees.
import Foundation
import IOKit.hid

let transport = CommandLine.arguments[1], secs = Double(CommandLine.arguments[2])!
let buttonsOnly = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "buttons"
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
var samples: [Double] = []
var last: [UInt8] = []
var events: [String: Int] = [:]

// Bytes that carry digital inputs: 8 = hat/strum (low nibble) + buttons, 9–11 = buttons,
// 43 = fret bitmask. Whammy (41), tilt (42), counter (12–15) and CRC (56–63) are ignored.
let buttonBytes = [8, 9, 10, 11, 43]

let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x0e6f, kIOHIDProductIDKey: 0x0249, kIOHIDTransportKey: transport] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let r = IOHIDManagerOpen(m, 0)
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
let devs = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []
print("open:", String(format: "0x%x", r), "devices:", devs.count, buttonsOnly ? "(button/strum changes only)" : "(all reports)")
for d in devs {
    IOHIDDeviceRegisterInputReportWithTimeStampCallback(d, buf, 256, { _, _, _, _, _, report, len, ts in
        let now = mach_absolute_time()
        let b = Array(UnsafeBufferPointer(start: report, count: len))
        defer { last = b }
        if buttonsOnly {
            guard last.count == b.count, b.count > 43 else { return }
            let changed = buttonBytes.filter { b[$0] != last[$0] }
            guard !changed.isEmpty else { return }
            let kind = changed == [8] && (b[8] & 0xF0) == (last[8] & 0xF0) ? "strum/d-pad" : "frets/buttons"
            events[kind, default: 0] += 1
        }
        samples.append(Double(now &- ts) * Double(tb.numer) / Double(tb.denom) / 1000.0) // µs
    }, nil)
}
CFRunLoopRunInMode(.defaultMode, secs, false)

let s = samples.sorted()
func pct(_ p: Double) -> Double { s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * p))] }
if buttonsOnly { print("events:", events) }
let spikes = s.filter { $0 > 2000 }
print("spikes >2ms:", spikes.count, spikes.map { Int($0) })
print(String(format: "%@: n=%d  median %.0f µs  p90 %.0f µs  p99 %.0f µs  max %.0f µs",
             transport, s.count, pct(0.5), pct(0.9), pct(0.99), s.last ?? .nan))
