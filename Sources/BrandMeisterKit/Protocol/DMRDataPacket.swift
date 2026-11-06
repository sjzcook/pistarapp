import Foundation

/// DMR 数据类型（对应 MMDVM `DMRDefines.h` 的 `DMRDataType`）。
public enum DMRDataType: UInt8 {
    case idle = 0x00
    case voicePIHeader = 0x01
    case voiceLCHeader = 0x02
    case terminatorWithLC = 0x03
    case csbk = 0x04
    case dataHeader = 0x06
    case rate12Data = 0x07
    case rate34Data = 0x08
    case idleSTC = 0x09
    case rate1Data = 0x0A

    /// 一次通话的开始：语音链路控制头。
    public var isCallStart: Bool { self == .voiceLCHeader }
    /// 一次通话的结束：带链路控制的终结帧。
    public var isCallEnd: Bool { self == .terminatorWithLC }
}

/// Homebrew 协议里的 55 字节 DMRD 包。
///
/// 字节布局（与 DMRGateway `CDMRNetwork::read/write` 完全一致）：
/// ```
/// 0..3   "DMRD"
/// 4      Sequence No
/// 5..7   Source ID      (24bit BE)
/// 8..10  Dest ID        (24bit BE)
/// 11..14 Repeater ID    (32bit BE)
/// 15     Flags          bit7 时隙 / bit6 个呼 / bit5 数据同步 / bit4 语音同步 / bit0..3 N 或数据类型
/// 16..19 Stream ID
/// 20..52 DMR Payload    (33 字节)
/// 53     BER
/// 54     RSSI
/// ```
public struct DMRDataPacket: Equatable {
    public enum FrameKind: Equatable {
        /// 普通语音帧，携带帧序号 N(0...5)。
        case voiceFrame(UInt8)
        /// 语音同步帧（每个超帧的第 1 帧）。
        case voiceSync
        /// 数据帧，携带 `DMRDataType` 原始值。
        case data(UInt8)
    }

    public var sequence: UInt8
    public var sourceID: UInt32
    public var destinationID: UInt32
    public var repeaterID: UInt32
    /// 1 或 2。
    public var slot: Int
    /// true 表示个呼（private call），false 表示组呼。
    public var isPrivate: Bool
    public var kind: FrameKind
    public var streamID: UInt32
    /// 33 字节 DMR 负载。
    public var payload: [UInt8]
    public var bitErrorRate: UInt8
    public var rssi: UInt8

    public init?(_ bytes: [UInt8]) {
        guard bytes.count >= HBP.dataPacketLength,
              String(decoding: bytes[0..<4], as: UTF8.self) == "DMRD" else { return nil }

        sequence = bytes[4]
        sourceID = bytes.beUInt24(5)
        destinationID = bytes.beUInt24(8)
        repeaterID = bytes.beUInt32(11)

        let flags = bytes[15]
        slot = (flags & 0x80) != 0 ? 2 : 1
        isPrivate = (flags & 0x40) != 0
        switch (flags >> 4) & 0x03 {
        case 0b00: kind = .voiceFrame(flags & 0x0F)
        case 0b01: kind = .voiceSync
        default: kind = .data(flags & 0x0F)
        }

        streamID = bytes.beUInt32(16)
        payload = Array(bytes[20..<53])
        bitErrorRate = bytes[53]
        rssi = bytes[54]
    }

    public init(sequence: UInt8,
                sourceID: UInt32,
                destinationID: UInt32,
                repeaterID: UInt32,
                slot: Int,
                isPrivate: Bool,
                kind: FrameKind,
                streamID: UInt32,
                payload: [UInt8],
                bitErrorRate: UInt8 = 0,
                rssi: UInt8 = 0) {
        self.sequence = sequence
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.repeaterID = repeaterID
        self.slot = slot
        self.isPrivate = isPrivate
        self.kind = kind
        self.streamID = streamID
        self.payload = payload
        self.bitErrorRate = bitErrorRate
        self.rssi = rssi
    }

    /// 数据帧对应的类型；语音帧返回 nil。
    public var dataType: DMRDataType? {
        if case .data(let raw) = kind { return DMRDataType(rawValue: raw) }
        return nil
    }

    /// 是否为语音（含同步帧）。
    public var isVoice: Bool {
        switch kind {
        case .voiceFrame, .voiceSync: return true
        case .data: return false
        }
    }

    /// 序列化回 55 字节，用于回传（本工程默认只听不发，保留以对齐 Pi-Star 的双工路径）。
    public func encoded() -> [UInt8] {
        var bytes = HBP.data
        bytes.append(sequence)
        bytes += sourceID.beUInt24Bytes
        bytes += destinationID.beUInt24Bytes
        bytes += repeaterID.bigEndianBytes

        var flags: UInt8 = slot == 2 ? 0x80 : 0x00
        if isPrivate { flags |= 0x40 }
        switch kind {
        case .voiceFrame(let n): flags |= (n & 0x0F)
        case .voiceSync: flags |= 0x10
        case .data(let t): flags |= 0x20 | (t & 0x0F)
        }
        bytes.append(flags)

        bytes += streamID.bigEndianBytes
        bytes += Array(payload.prefix(HBP.payloadLength))
        while bytes.count < 53 { bytes.append(0) }
        bytes.append(bitErrorRate)
        bytes.append(rssi)
        return bytes
    }
}
