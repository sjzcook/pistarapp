import Foundation

extension Array where Element == UInt8 {
    /// 读取 24 位大端整数（DMR ID 用 3 字节表示）。
    func beUInt24(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) << 16 | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2])
    }

    /// 读取 32 位大端整数。
    func beUInt32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    /// 调试用的十六进制字符串。
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension UInt32 {
    /// 转为 4 字节大端，用于写回协议包。
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 24) & 0xFF),
         UInt8((self >> 16) & 0xFF),
         UInt8((self >> 8) & 0xFF),
         UInt8(self & 0xFF)]
    }

    /// 转为 3 字节大端（DMR ID 字段）。
    var beUInt24Bytes: [UInt8] {
        [UInt8((self >> 16) & 0xFF),
         UInt8((self >> 8) & 0xFF),
         UInt8(self & 0xFF)]
    }
}
