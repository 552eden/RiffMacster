// Report-descriptor patching for the PDP RiffMaster (PS5), VID 0x0E6F / PID 0x0249.
//
// The guitar declares bytes 12–63 of input report 1 as one 52-byte vendor blob.
// Whammy (byte 41) and tilt (byte 42) live inside it, so macOS never exposes them.
// We split the blob so those two bytes become Generic Desktop Slider / Dial axes.
// The report layout stays identical; only bytes 41/42 are rescaled (see `transform`).
//
// Rest position: whammy and tilt rest at their *minimum*, but games (Rewired / Clone Hero)
// assume an axis rests at its *center*, which is why they needed manual calibration.
// So the axes are declared signed (-127…127) and the raw 0…255 value is halved to 0…127:
// rest = center = 0, fully pressed / vertical = +1. Default calibration is then correct.

enum Descriptor {
    /// The vendor-blob input item as the guitar declares it:
    /// Usage Page (0xFF00), Usage (0x22), Logical Min 0, Logical Max 255,
    /// Report Size 8, Report Count 52, Input (Data,Var,Abs).
    static let original: [UInt8] = [
        0x06, 0x00, 0xFF, 0x09, 0x22, 0x15, 0x00, 0x26, 0xFF, 0x00,
        0x75, 0x08, 0x95, 0x34, 0x81, 0x02,
    ]

    /// Replacement: 29 vendor bytes (12–40), Slider = whammy (41),
    /// Dial = tilt (42), 21 vendor bytes (43–63). Still 52 bytes total.
    static let replacement: [UInt8] = [
        0x06, 0x00, 0xFF, 0x09, 0x22, 0x15, 0x00, 0x26, 0xFF, 0x00,
        0x75, 0x08, 0x95, 0x1D, 0x81, 0x02,             // 29 vendor bytes
        0x05, 0x01, 0x09, 0x36, 0x15, 0x81, 0x25, 0x7F, // Slider (whammy), logical -127…127
        0x95, 0x01, 0x81, 0x02,
        0x09, 0x37, 0x81, 0x02,                         // Dial (tilt), same range
        0x06, 0x00, 0xFF, 0x09, 0x22, 0x15, 0x00, 0x26, 0xFF, 0x00, // back to 0…255
        0x95, 0x15, 0x81, 0x02,                         // 21 vendor bytes
    ]

    static let whammyByte = 41, tiltByte = 42

    /// Rescales whammy/tilt in an input report (report-ID byte at index 0) from
    /// 0…255 to 0…127, matching the signed center-rest axes declared above.
    @inline(__always)
    static func transform(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard length > tiltByte, report[0] == 0x01 else { return }
        report[whammyByte] >>= 1
        report[tiltByte] >>= 1
    }

    /// Returns the patched descriptor, or nil if the expected item isn't found
    /// exactly once (e.g. a firmware update changed the layout). We refuse to
    /// guess in that case.
    static func patch(_ d: [UInt8]) -> [UInt8]? {
        var matches: [Int] = []
        if d.count >= original.count {
            for i in 0...(d.count - original.count) where Array(d[i..<i + original.count]) == original {
                matches.append(i)
            }
        }
        guard matches.count == 1, let at = matches.first else { return nil }
        return Array(d[..<at]) + replacement + Array(d[(at + original.count)...])
    }
}

/// Minimal HID descriptor parser, used only by `--selftest` to prove that the
/// patched descriptor puts whammy/tilt at the right byte offsets.
struct HIDField: CustomStringConvertible {
    let reportID: UInt8, usagePage: UInt32, usage: UInt32, bitOffset: Int, bitSize: Int
    let logicalMin: Int, logicalMax: Int
    var description: String {
        String(format: "report %d page 0x%X usage 0x%X @ bit %d (%d bits, %d…%d)", reportID, usagePage, usage, bitOffset, bitSize, logicalMin, logicalMax)
    }
}

enum HIDParser {
    /// Parses input fields. Bit offsets exclude the report-ID byte.
    static func inputFields(_ d: [UInt8]) -> (fields: [HIDField], bitsPerReport: [UInt8: Int]) {
        var fields: [HIDField] = []
        var bits: [UInt8: Int] = [:]
        var usagePage: UInt32 = 0, reportSize = 0, reportCount = 0, reportID: UInt8 = 0
        var logicalMin = 0, logicalMax = 0
        var usages: [UInt32] = []
        var usageMin: UInt32?
        var i = 0
        while i < d.count {
            let prefix = d[i]
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            let tag = prefix & 0xFC
            var value: UInt32 = 0
            for k in 0..<size where i + 1 + k < d.count { value |= UInt32(d[i + 1 + k]) << (8 * k) }
            i += 1 + size
            switch tag {
            case 0x04: usagePage = value
            case 0x14: logicalMin = signed(value, size)
            case 0x24: logicalMax = signed(value, size)
            case 0x74: reportSize = Int(value)
            case 0x94: reportCount = Int(value)
            case 0x84: reportID = UInt8(value)
            case 0x08: usages.append(size == 4 ? value & 0xFFFF : value)
            case 0x18: usageMin = value
            case 0x28: if let lo = usageMin { usages += Array(lo...value) }; usageMin = nil
            case 0x80: // Input
                var off = bits[reportID, default: 0]
                for n in 0..<reportCount {
                    let u = usages.isEmpty ? 0 : usages[min(n, usages.count - 1)]
                    fields.append(HIDField(reportID: reportID, usagePage: usagePage, usage: u, bitOffset: off, bitSize: reportSize,
                                           logicalMin: logicalMin, logicalMax: logicalMax))
                    off += reportSize
                }
                bits[reportID] = off
                usages = []
            case 0x90, 0xB0, 0xA0, 0xC0: usages = [] // Output / Feature / Collection / End
            default: break
            }
        }
        return (fields, bits)
    }

    private static func signed(_ v: UInt32, _ size: Int) -> Int {
        switch size {
        case 1: return Int(Int8(truncatingIfNeeded: v))
        case 2: return Int(Int16(truncatingIfNeeded: v))
        case 4: return Int(Int32(bitPattern: v))
        default: return 0
        }
    }
}
