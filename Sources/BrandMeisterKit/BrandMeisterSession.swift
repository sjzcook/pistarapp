import Foundation

/// 运行状态统计，用来判断「连上了但没声音」到底是哪一层断了。
public struct SessionHealth {
    public var bursts = 0
    public var voiceBursts = 0
    public var callsHeard = 0
    public var ambeBlocks = 0
    public var decodedFrames = 0
    public var lastHeardAt: Date?
    public var lastSourceID: UInt32?
    public var lastRSSI: UInt8 = 0
    public var lastBER: UInt8 = 0

    public init() {}
}

public enum SessionEvent {
    case state(ClientState)
    case callStarted(CallSession)
    case callEnded(CallSummary)
    case log(String)
    case error(String)
    case health(SessionHealth)
}

/// 对外的门面：把协议客户端、通话跟踪、声码器、播放器串起来。
public final class BrandMeisterSession {

    public struct Options {
        public var client: HomebrewClient.Configuration
        /// 为空表示监听全部；否则只处理这些通话组/ID。
        public var watchTalkgroups: Set<UInt32>
        public var audioEnabled: Bool
        public var decoder: VoiceDecoder
        public var callTimeout: TimeInterval

        public init(client: HomebrewClient.Configuration,
                    watchTalkgroups: Set<UInt32> = [],
                    audioEnabled: Bool = false,
                    decoder: VoiceDecoder = NullVoiceDecoder(),
                    callTimeout: TimeInterval = 1.2) {
            self.client = client
            self.watchTalkgroups = watchTalkgroups
            self.audioEnabled = audioEnabled
            self.decoder = decoder
            self.callTimeout = callTimeout
        }
    }

    public var onEvent: ((SessionEvent) -> Void)?
    public private(set) var health = SessionHealth()

    private let options: Options
    private let client: HomebrewClient
    private let tracker = CallTracker()
    private let player: PCMAudioPlayer?
    private var audioStartFailed = false

    public init(options: Options) {
        self.options = options
        self.client = HomebrewClient(configuration: options.client)
        self.player = options.audioEnabled ? PCMAudioPlayer() : nil

        tracker.callTimeout = options.callTimeout
        tracker.onCallStarted = { [weak self] session in
            guard let self else { return }
            self.health.callsHeard += 1
            self.emit(.callStarted(session))
            self.emit(.health(self.health))
        }
        tracker.onCallEnded = { [weak self] summary in
            guard let self else { return }
            self.emit(.callEnded(summary))
            self.emit(.health(self.health))
        }
        tracker.onVoiceBurst = { [weak self] session, packet in
            self?.handleVoiceBurst(session: session, packet: packet)
        }

        client.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .stateChanged(let state):
                self.emit(.state(state))
            case .log(let message):
                self.emit(.log(message))
            case .error(let message):
                self.emit(.error(message))
            case .packet(let packet):
                self.handle(packet)
            }
        }
    }

    public func start() {
        client.start()
    }

    public func stop() {
        client.stop()
        tracker.reset()
        player?.stop()
    }

    public var activeCalls: [CallSession] { tracker.activeCalls }

    // MARK: - 内部

    private func handle(_ packet: DMRDataPacket) {
        health.bursts += 1
        health.lastHeardAt = Date()
        health.lastSourceID = packet.sourceID
        health.lastRSSI = packet.rssi
        health.lastBER = packet.bitErrorRate

        // 通话组过滤：只关心自己订阅的 TG（个呼直通）。
        if !options.watchTalkgroups.isEmpty,
           !packet.isPrivate,
           !options.watchTalkgroups.contains(packet.destinationID) {
            return
        }

        if packet.isVoice { health.voiceBursts += 1 }
        tracker.process(packet)
    }

    private func handleVoiceBurst(session: CallSession, packet: DMRDataPacket) {
        let blocks = DMRVoicePayload.ambeBlocks(from: packet.payload)
        guard !blocks.isEmpty else { return }
        health.ambeBlocks += blocks.count

        guard options.audioEnabled else { return }
        if let player, !player.isRunning, !audioStartFailed {
            do {
                try player.start(sampleRate: options.decoder.sampleRate)
            } catch {
                audioStartFailed = true
                emit(.error("音频输出启动失败: \(error.localizedDescription)"))
            }
        }
        for block in blocks {
            guard let samples = options.decoder.decode(block: block) else { continue }
            health.decodedFrames += 1
            player?.play(samples)
        }
    }

    private func emit(_ event: SessionEvent) {
        onEvent?(event)
    }
}
