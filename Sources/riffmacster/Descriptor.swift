// Report-descriptor patching for the PDP RiffMaster (PS5), VID 0x0E6F / PID 0x0249.
//
// The guitar declares bytes 12–63 of input report 1 as one 52-byte vendor blob.
// Whammy (byte 41) and tilt (byte 42) live inside it, so macOS never exposes them.
// We split the blob so those two bytes become Generic Desktop Slider / Dial axes.
// The report layout stays identical, so real reports can be forwarded unchanged.

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
        0x75, 0x08, 0x95, 0x1D, 0x81, 0x02,        // 29 vendor bytes
        0x05, 0x01, 0x09, 0x36, 0x95, 0x01, 0x81, 0x02, // Slider (whammy)
        0x09, 0x37, 0x81, 0x02,                    // Dial (tilt)
        0x06, 0x00, 0xFF, 0x09, 0x22, 0x95, 0x15, 0x81, 0x02, // 21 vendor bytes
    ]

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
    var description: String {
        String(format: "report %d page 0x%X usage 0x%X @ bit %d (%d bits)", reportID, usagePage, usage, bitOffset, bitSize)
    }
}

enum HIDParser {
    /// Parses input fields. Bit offsets exclude the report-ID byte.
    static func inputFields(_ d: [UInt8]) -> (fields: [HIDField], bitsPerReport: [UInt8: Int]) {
        var fields: [HIDField] = []
        var bits: [UInt8: Int] = [:]
        var usagePage: UInt32 = 0, reportSize = 0, reportCount = 0, reportID: UInt8 = 0
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
                    fields.append(HIDField(reportID: reportID, usagePage: usagePage, usage: u, bitOffset: off, bitSize: reportSize))
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
}
