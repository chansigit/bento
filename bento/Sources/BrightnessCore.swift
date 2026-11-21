import Foundation

// MARK: - Pure DDC/CI helpers (testable, no IOKit side effects)

/// Build the DDC/CI "Set VCP Feature" I²C payload for a monitor control.
/// Layout: [length|opcode 0x84, command 0x03, vcp, valueHi, valueLo, checksum].
/// The checksum XORs the destination address byte 0x6e (0x37<<1) as DDC requires.
func ddcSetVCPPayload(vcp: UInt8, value: UInt16) -> [UInt8] {
    let hi = UInt8(value >> 8)
    let lo = UInt8(value & 0xFF)
    let d0: UInt8 = 0x84
    let d1: UInt8 = 0x03
    let checksum = 0x6e ^ 0x51 ^ d0 ^ d1 ^ vcp ^ hi ^ lo
    return [d0, d1, vcp, hi, lo, checksum]
}

/// Clamp a brightness percentage into the valid 0...100 range.
func clampBrightnessPercent(_ percent: Int) -> Int {
    return min(100, max(0, percent))
}

func ddcGetVCPPayload(vcp: UInt8) -> [UInt8] {
    return [0x82, 0x01, vcp, 0x6e ^ 0x51 ^ 0x82 ^ 0x01 ^ vcp]
}

struct DDCValue: Equatable {
    let current: UInt16
    let maximum: UInt16

    var percent: Int {
        guard maximum > 0 else { return 0 }
        return clampBrightnessPercent(Int((Double(current) * 100 / Double(maximum)).rounded()))
    }

    func rawValue(percent: Int) -> UInt16 {
        return UInt16((Double(clampBrightnessPercent(percent)) * Double(maximum) / 100).rounded())
    }
}

func parseDDCValue(_ bytes: [UInt8], vcp: UInt8) -> DDCValue? {
    guard bytes.count >= 11, bytes[0] == 0x6e, bytes[1] == 0x88,
          bytes[2] == 0x02, bytes[3] == 0, bytes[4] == vcp, bytes[5] == 0,
          bytes.prefix(11).reduce(UInt8(0x50), ^) == 0 else { return nil }
    let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
    let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
    guard maximum > 0, current <= maximum else { return nil }
    return DDCValue(current: current, maximum: maximum)
}
