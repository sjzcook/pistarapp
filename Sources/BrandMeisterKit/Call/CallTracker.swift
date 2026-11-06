import Foundation

/// 从 DMRD 流里还原「一通电话」的生命周期。
///
/// DMR 的一次组呼在空口上是这样组织的：
/// ```
/// VOICE_LC_HEADER (0x02)     ← 呼叫开始，带源/目的/时隙
/// VOICE_SYNC / VOICE(N)      ← 语音帧，每个 burst 3 个 AMBE 块
/// ... 反复 ...
/// TERMINATOR_WITH_LC (0x03)  ← 呼叫结束
/// ```
/// 主站有时会漏掉头/尾（丢包、中途接入），所以这里同时用「静默超时」兜底。
public final class CallTracker {

    /// 超过这个时间没有新 burst 就认为通话结束。
    public var callTimeout: TimeInterval = 1.2

    public var onCallStarted: ((CallSession) -> Void)?
    public var onCallEnded: ((CallSummary) -> Void)?
    /// 收到语音 burst（一次 60ms，含 3 个 AMBE 块）。
    public var onVoiceBurst: ((CallSession, DMRDataPacket) -> Void)?

    private struct CacheKey: Hashable {
        let slot: Int
        let source: UInt32
        let destination: UInt32
    }

    private var active: [CacheKey: CallSession] = [:]
    private var order: [CacheKey] = []

    public init() {}

    public var activeCalls: [CallSession] {
        order.compactMap { active[$0] }
    }

    public func reset() {
        active.removeAll()
        order.removeAll()
    }

    public func process(_ packet: DMRDataPacket, now: Date = Date()) {
        expire(now: now)

        let cacheKey = CallTracker.cacheKey(for: packet)

        if let type = packet.dataType {
            if type.isCallStart {
                start(packet, at: now, frameCount: 0)
            } else if type.isCallEnd {
                if let session = active[cacheKey] {
                    end(session, at: now)
                }
            }
            // 其余数据类型（CSBK、GPS、短信等）当前不处理。
            return
        }

        // 语音帧：没有头也能靠第一帧起呼。
        if var session = active[cacheKey] {
            session.frameCount += 1
            session.lastHeardAt = now
            active[cacheKey] = session
            onVoiceBurst?(session, packet)
        } else {
            let session = start(packet, at: now, frameCount: 1)
            onVoiceBurst?(session, packet)
        }
    }

    /// 外部定时清理静默通话（不依赖是否有新包到达）。
    public func expireStale(now: Date = Date()) {
        expire(now: now)
    }

    // MARK: - 内部

    private static func cacheKey(for packet: DMRDataPacket) -> CacheKey {
        CacheKey(slot: packet.slot, source: packet.sourceID, destination: packet.destinationID)
    }

    @discardableResult
    private func start(_ packet: DMRDataPacket, at date: Date, frameCount: Int) -> CallSession {
        let cacheKey = CallTracker.cacheKey(for: packet)
        if let existing = active[cacheKey] {
            end(existing, at: date)
        }
        let session = CallSession(slot: packet.slot,
                                  sourceID: packet.sourceID,
                                  destinationID: packet.destinationID,
                                  isPrivate: packet.isPrivate,
                                  startedAt: date,
                                  lastHeardAt: date,
                                  frameCount: frameCount)
        active[cacheKey] = session
        if !order.contains(cacheKey) { order.append(cacheKey) }
        onCallStarted?(session)
        return session
    }

    private func end(_ session: CallSession, at date: Date) {
        let cacheKey = CacheKey(slot: session.slot,
                                source: session.sourceID,
                                destination: session.destinationID)
        active.removeValue(forKey: cacheKey)
        order.removeAll { $0 == cacheKey }
        onCallEnded?(CallSummary(id: session.id,
                                 slot: session.slot,
                                 sourceID: session.sourceID,
                                 destinationID: session.destinationID,
                                 isPrivate: session.isPrivate,
                                 startedAt: session.startedAt,
                                 endedAt: date,
                                 frameCount: session.frameCount))
    }

    private func expire(now: Date) {
        for cacheKey in order {
            guard let session = active[cacheKey] else { continue }
            if now.timeIntervalSince(session.lastHeardAt) > callTimeout {
                end(session, at: session.lastHeardAt)
            }
        }
    }
}
