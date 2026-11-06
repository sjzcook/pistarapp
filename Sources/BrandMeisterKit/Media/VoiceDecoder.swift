import Foundation

/// 声码器抽象层。
///
/// DMR 用 AMBE+2（DVSI 专利），必须外挂解码器才能出声：
/// - 默认用 `NullVoiceDecoder`：链路、通话、帧全部正常，只是不产生 PCM；
/// - 接入 mbelib 后实现 `decode(block:)` 返回 8kHz 单声道 PCM 即可出声。
public protocol VoiceDecoder: AnyObject {
    /// 输出采样率，DMR 固定 8000Hz。
    var sampleRate: Double { get }
    /// 解一个 72bit AMBE 块，返回 160 个采样点（20ms @8kHz）。
    func decode(block: [UInt8]) -> [Int16]?
    func reset()
}

/// 空解码器：统计帧数，不出声。用于验证链路是否通、通话是否被正确还原。
public final class NullVoiceDecoder: VoiceDecoder {
    public let sampleRate: Double = 8000
    public private(set) var decodedBlocks = 0
    public private(set) var lastError: String?

    public init() {}

    public func decode(block: [UInt8]) -> [Int16]? {
        decodedBlocks += 1
        return nil
    }

    public func reset() {
        decodedBlocks = 0
        lastError = nil
    }
}
