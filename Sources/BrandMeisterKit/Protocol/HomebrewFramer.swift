import Foundation

/// 主站回包。
public enum HomebrewPacket: Equatable {
    /// RPTACK，负载 4 字节：登录阶段是 challenge/salt，其后是回显的 ID。
    case repeaterAck(value: UInt32)
    /// MSTPONG，心跳回应。
    case masterPong(repeaterID: UInt32)
    /// MSTNAK，主站拒绝。
    case masterNak(repeaterID: UInt32)
    /// MSTCL，主站主动断开。
    case masterClosed(repeaterID: UInt32)
    /// RPTSBKN，要求发送信标。
    case beacon
    /// DMRD 语音/数据包。
    case dmrData(DMRDataPacket)
    case other(prefix: String, bytes: [UInt8])

    init?(bytes: [UInt8]) {
        guard bytes.count >= 4 else { return nil }
        switch String(decoding: bytes[0..<4], as: UTF8.self) {
        case "RPTA":
            guard bytes.count >= 10 else { return nil }
            self = .repeaterAck(value: bytes.beUInt32(6))
        case "MSTP":
            guard bytes.count >= 11 else { return nil }
            self = .masterPong(repeaterID: bytes.beUInt32(7))
        case "MSTN":
            guard bytes.count >= 10 else { return nil }
            self = .masterNak(repeaterID: bytes.beUInt32(6))
        case "MSTC":
            guard bytes.count >= 9 else { return nil }
            self = .masterClosed(repeaterID: bytes.beUInt32(5))
        case "RPTS":
            self = .beacon
        case "DMRD":
            guard let packet = DMRDataPacket(bytes) else { return nil }
            self = .dmrData(packet)
        default:
            self = .other(prefix: String(decoding: bytes[0..<4], as: UTF8.self), bytes: bytes)
        }
    }
}

/// TCP 是字节流，必须自己按报文长度切包——
/// 否则两个 DMRD 粘在一个 recv 里就会被丢掉（Pi-Star 用 UDP 所以没这个问题）。
public struct HomebrewFramer {
    private var buffer: [UInt8] = []
    private let maxBuffer = 64 * 1024

    /// 因为报文无法对齐而被丢弃的字节数，便于排查异常主站。
    public private(set) var droppedBytes = 0

    public init() {}

    public mutating func append(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
        if buffer.count > maxBuffer {
            droppedBytes += buffer.count
            buffer.removeAll(keepingCapacity: true)
        }
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// 取下一个完整报文；不足一包时返回 nil。
    public mutating func next() -> HomebrewPacket? {
        guard buffer.count >= 4 else { return nil }
        let prefix = String(decoding: buffer[0..<4], as: UTF8.self)
        guard let length = HomebrewFramer.length(for: prefix) else {
            // 无法识别的报文：丢掉整个缓冲重新找同步头。
            droppedBytes += buffer.count
            buffer.removeAll(keepingCapacity: true)
            return nil
        }
        guard buffer.count >= length else { return nil }
        let raw = Array(buffer[0..<length])
        buffer.removeFirst(length)
        return HomebrewPacket(bytes: raw)
    }

    static func length(for prefix: String) -> Int? {
        switch prefix {
        case "RPTA": return 10              // RPTACK + 4
        case "MSTP": return 11              // MSTPONG + 4
        case "MSTN": return 10              // MSTNAK + 4
        case "MSTC": return 9               // MSTCL + 4
        case "RPTS": return 7               // RPTSBKN
        case "DMRD": return HBP.dataPacketLength
        default: return nil
        }
    }
}
