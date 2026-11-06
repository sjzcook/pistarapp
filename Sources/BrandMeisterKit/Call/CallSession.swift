import Foundation

/// 一通正在进行的通话。
public struct CallSession: Identifiable, Equatable {
    public let id: UUID
    public let slot: Int
    public let sourceID: UInt32
    public let destinationID: UInt32
    public let isPrivate: Bool
    public let startedAt: Date
    public var lastHeardAt: Date
    public var frameCount: Int

    public init(id: UUID = UUID(),
                slot: Int,
                sourceID: UInt32,
                destinationID: UInt32,
                isPrivate: Bool,
                startedAt: Date,
                lastHeardAt: Date,
                frameCount: Int) {
        self.id = id
        self.slot = slot
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.isPrivate = isPrivate
        self.startedAt = startedAt
        self.lastHeardAt = lastHeardAt
        self.frameCount = frameCount
    }

    /// 组呼时即通话组号，个呼时是对方 DMR ID。
    public var talkgroup: UInt32 { destinationID }

    public var duration: TimeInterval { lastHeardAt.timeIntervalSince(startedAt) }

    /// 通话已持续的语音帧数换算时长（每帧 60ms）。
    public var voiceDuration: TimeInterval { Double(frameCount) * 0.06 }
}

/// 通话结束后的摘要。
public struct CallSummary: Identifiable, Equatable {
    public let id: UUID
    public let slot: Int
    public let sourceID: UInt32
    public let destinationID: UInt32
    public let isPrivate: Bool
    public let startedAt: Date
    public let endedAt: Date
    public let frameCount: Int

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public var talkgroup: UInt32 { destinationID }
}
