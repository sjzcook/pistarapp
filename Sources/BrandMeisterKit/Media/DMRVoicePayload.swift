import Foundation

/// 把 33 字节 DMR 负载拆成 AMBE+2 声码器块。
///
/// 一个 DMR burst 的 264 bit 结构：
/// ```
/// 6 字节  同步 / 嵌入信令 / 时隙类型信息
/// 9 字节  AMBE 块 #0  (72bit，含 FEC)
/// 9 字节  AMBE 块 #1
/// 9 字节  AMBE 块 #2
/// ```
/// 每个语音 burst 正好覆盖 60ms（3 × 20ms 声码器帧），与时隙 60ms 周期吻合。
///
/// 注意：这里只做「拆块」，不做 FEC 纠错与 AMBE 解码——那一步需要 mbelib
/// （AMBE+2 是 DVSI 的专利算法，开源实现只有 mbelib）。见 README「语音解码」。
public enum DMRVoicePayload {
    /// 负载前面的同步/时隙类型字节数。
    public static let headerLength = 6
    public static let blockLength = 9
    public static let blocksPerBurst = 3

    /// 取出 3 个 72bit AMBE 块；负载长度不足时返回空数组。
    /// - Parameter headerLength: 同步/时隙类型占用的字节数，默认 6（6 + 27 = 33）。
    public static func ambeBlocks(from payload: [UInt8],
                                  headerLength: Int = DMRVoicePayload.headerLength) -> [[UInt8]] {
        guard payload.count >= headerLength + blocksPerBurst * blockLength else { return [] }
        return (0..<blocksPerBurst).map { index in
            let start = headerLength + index * blockLength
            return Array(payload[start..<(start + blockLength)])
        }
    }

    /// 把若干 burst 的 AMBE 块串成连续流，方便一次性交给解码器。
    public static func appendBlocks(from payload: [UInt8], to sink: inout [[UInt8]]) {
        sink.append(contentsOf: ambeBlocks(from: payload))
    }
}
