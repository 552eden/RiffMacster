// RiffMacster: exposes the PDP RiffMaster (PS5) whammy and tilt on macOS.
//
// Seizes the real guitar, publishes a virtual HID guitar with a corrected report
// descriptor, and forwards every input report byte-for-byte. Started by launchd
// when the guitar connects; exits when it disconnects.

import Foundation
import IOKit.hid
import XPC
import os

let vendorID = 0x0E6F
let productID = 0x0249
let virtualName = "RiffMaster (RiffMacster)"
let log = Logger(subsystem: "com.riffmacster", category: "helper")

var foreground = false
func say(_ msg: String, error: Bool = false) {
    if error { log.error("\(msg, privacy: .public)") } else { log.notice("\(msg, privacy: .public)") }
    if foreground { FileHandle.standardError.write(Data("riffmacster: \(msg)\n".utf8)) }
}

// MARK: - State (C callbacks can't capture, so state is global and main-queue only)

var realDevice: IOHIDDevice?
var virtualDevice: IOHIDUserDevice?
let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
var reportsForwarded = 0

// MARK: - Virtual device

func makeVirtualDevice(from real: IOHIDDevice, descriptor: [UInt8]) -> IOHIDUserDevice? {
    func prop(_ key: String) -> Any? { IOHIDDeviceGetProperty(real, key as CFString) }
    var props: [String: Any] = [
        kIOHIDReportDescriptorKey: Data(descriptor),
        kIOHIDVendorIDKey: vendorID,
        kIOHIDProductIDKey: productID,
        kIOHIDProductKey: virtualName,
        kIOHIDManufacturerKey: prop(kIOHIDManufacturerKey) ?? "PDP",
        kIOHIDTransportKey: "Virtual", // keeps our own USB-only matching from grabbing it
        kIOHIDVersionNumberKey: prop(kIOHIDVersionNumberKey) ?? 0x101,
        kIOHIDCountryCodeKey: 0,
    ]
    if let serial = prop(kIOHIDSerialNumberKey) { props[kIOHIDSerialNumberKey] = serial }

    guard let dev = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, props as CFDictionary, 0) else {
        return nil
    }

    // Pass feature/output requests from games straight through to the real guitar.
    IOHIDUserDeviceRegisterGetReportBlock(dev) { type, reportID, report, length in
        guard let real = realDevice else { return kIOReturnNotAttached }
        return IOHIDDeviceGetReport(real, type, CFIndex(reportID), report, length)
    }
    IOHIDUserDeviceRegisterSetReportBlock(dev) { type, reportID, report, length in
        guard let real = realDevice else { return kIOReturnNotAttached }
        return IOHIDDeviceSetReport(real, type, CFIndex(reportID), report, length)
    }
    IOHIDUserDeviceSetDispatchQueue(dev, .main)
    IOHIDUserDeviceActivate(dev)
    return dev
}

// MARK: - Real device lifecycle

let inputCallback: IOHIDReportWithTimeStampCallback = { _, result, _, _, _, report, length, timestamp in
    guard result == kIOReturnSuccess, let vdev = virtualDevice else { return }
    IOHIDUserDeviceHandleReportWithTimeStamp(vdev, timestamp, report, length)
    reportsForwarded += 1
}

func attach(_ dev: IOHIDDevice) {
    guard realDevice == nil else { return }

    guard let raw = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data else {
        say("could not read the guitar's report descriptor", error: true); exit(1)
    }
    guard let patched = Descriptor.patch([UInt8](raw)) else {
        say("unexpected report descriptor (firmware change?); refusing to guess", error: true); exit(1)
    }

    // Exclusive access, so games only see the corrected virtual guitar.
    var status = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    if status == kIOReturnSuccess {
        say("seized the real guitar")
    } else {
        say(String(format: "seize failed (0x%08x); opening shared, so games may see both guitars", status), error: true)
        status = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            say(String(format: "could not open the guitar (0x%08x)", status), error: true); exit(1)
        }
    }
    realDevice = dev

    guard let vdev = makeVirtualDevice(from: dev, descriptor: patched) else {
        say("could not create the virtual guitar (needs root: run with sudo or via launchd)", error: true); exit(1)
    }
    virtualDevice = vdev

    IOHIDDeviceRegisterInputReportWithTimeStampCallback(dev, reportBuffer, 256, inputCallback, nil)
    say("ready: \"\(virtualName)\" is live (whammy = Slider, tilt = Dial)")
}

func detach() {
    say("guitar disconnected after forwarding \(reportsForwarded) reports; exiting")
    if let vdev = virtualDevice { IOHIDUserDeviceCancel(vdev) }
    exit(0)
}

// MARK: - Self-test

func selftest() -> Int32 {
    // The descriptor read from a PS5 RiffMaster (ioreg ReportDescriptor).
    let hex = "05010905a1018501093009310932093509330934150026ff007508950681020600ff09209501810205010939150025073500463b016514750495018142650005091901290e150025017501950e81020600ff0921950e81020600ff0922150026ff0075089534810285020923952f910285030a2128952fb1020680ff85e009579502b102c006f0ff0940a10185f00947953fb10285f10948953fb10285f20949950fb102c0"
    var bytes: [UInt8] = []
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: 2)
        bytes.append(UInt8(hex[idx..<next], radix: 16)!)
        idx = next
    }
    guard let patched = Descriptor.patch(bytes) else { print("FAIL: patch did not apply"); return 1 }

    let before = HIDParser.inputFields(bytes), after = HIDParser.inputFields(patched)
    var ok = true
    func check(_ cond: Bool, _ what: String) { print(cond ? "ok   " : "FAIL ", what); ok = ok && cond }

    check(before.bitsPerReport[1] == 63 * 8, "original report 1 is 63 data bytes")
    check(after.bitsPerReport[1] == 63 * 8, "patched report 1 is still 63 data bytes")
    // Byte N of the raw report (counting the report-ID byte as 0) = bit (N-1)*8 here.
    let whammy = after.fields.first { $0.reportID == 1 && $0.usagePage == 1 && $0.usage == 0x36 }
    let tilt = after.fields.first { $0.reportID == 1 && $0.usagePage == 1 && $0.usage == 0x37 }
    check(whammy?.bitOffset == 40 * 8 && whammy?.bitSize == 8, "whammy (Slider) is byte 41")
    check(tilt?.bitOffset == 41 * 8 && tilt?.bitSize == 8, "tilt (Dial) is byte 42")
    let common = before.fields.prefix(while: { $0.usagePage != 0xFF00 || $0.usage != 0x22 }).count
    check(Array(before.fields.prefix(common)).map(\.description) == Array(after.fields.prefix(common)).map(\.description),
          "all original axes/hat/buttons unchanged (\(common) fields)")
    check(Descriptor.patch(patched) == nil, "patch refuses an already-patched descriptor")
    return ok ? 0 : 1
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
if args.contains("--selftest") { exit(selftest()) }
foreground = args.contains("--foreground")

if !foreground {
    // Launched by launchd for the IOKit matching event: consume the event,
    // otherwise launchd keeps relaunching us.
    xpc_set_event_stream_handler("com.apple.iokit.matching", .main) { _ in }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
    kIOHIDTransportKey: "USB",
] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, dev in attach(dev) }, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, dev in
    if dev == realDevice { detach() }
}, nil)
IOHIDManagerSetDispatchQueue(manager, .main)
IOHIDManagerActivate(manager)

// launchd fires on the USB device; the HID device can appear a moment later.
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    if realDevice == nil { say("no RiffMaster found within 10 s; exiting"); exit(0) }
}
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { say("stopping"); if let v = virtualDevice { IOHIDUserDeviceCancel(v) }; exit(0) }
    src.resume()
    signalSources.append(src)
}
say("waiting for the RiffMaster…")
dispatchMain()
