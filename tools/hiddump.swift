import Foundation
import IOKit.hid
let secs = Double(CommandLine.arguments.dropFirst().first ?? "15")!
let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x0e6f, kIOHIDProductIDKey: 0x0249] as CFDictionary)
var last = [UInt8]()
var lastKey = [UInt8]()
let cb: IOHIDReportCallback = { _, _, _, _, id, rep, len in
  let b = Array(UnsafeBufferPointer(start: rep, count: len))
  let key = b.enumerated().filter{ !(12...15).contains($0.offset) && $0.offset < 56 }.map{$0.element}; if key == lastKey { return }; lastKey = key
  var diff = ""
  if !last.isEmpty { for i in 0..<min(b.count,last.count) where b[i] != last[i] && !(12...15).contains(i) && i < 56 { diff += " [\(i)]\(last[i])->\(b[i])" } }
  last = b
  print(String(format:"%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)), "id\(id) len\(len):", b.map{String(format:"%02x",$0)}.joined(separator:" "), "|", diff)
  fflush(stdout)
}
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
IOHIDManagerRegisterDeviceMatchingCallback(m, { _, _, _, dev in
  print("matched", IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) ?? "")
}, nil)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("open:", IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)))
if let devs = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
  for d in devs { IOHIDDeviceRegisterInputReportCallback(d, buf, 128, cb, nil) }
}
CFRunLoopRunInMode(.defaultMode, secs, false)
