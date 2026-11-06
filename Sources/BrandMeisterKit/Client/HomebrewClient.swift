import Foundation
import Network

/// 链路层事件（相对底层，不含通话语义）。
public enum ClientEvent {
    case stateChanged(ClientState)
    case log(String)
    case packet(DMRDataPacket)
    case error(String)
}

/// Homebrew 客户端：负责 TCP 连接、登录握手、保活、断线重连。
///
/// 状态机与 Pi-Star 的 `CDMRNetwork` 保持一致：
/// ```
/// WAITING_CONNECT → RPTL → WAITING_LOGIN
///   ← RPTACK → RPTK → WAITING_AUTHENTICATION
///   ← RPTACK → RPTC → WAITING_CONFIG
///   ← RPTACK → RUNNING（每 5s RPTPING，60s 无数据判超时）
/// ```
public final class HomebrewClient {

    public struct Configuration {
        public var host: String
        public var port: UInt16
        /// 热点/中继的 DMR ID，登录时作为 repeater ID 上报。
        public var repeaterID: UInt32
        /// BrandMeister 自助页面里设置的 Hotspot 密码。
        public var password: String
        /// 上报给主站的配置；nil 时使用默认值。
        public var repeaterInfo: RepeaterInfo
        /// 是否发送 RPTC。个别主站不需要，遇到 MSTNAK 也会被当作非致命。
        public var sendConfiguration: Bool
        public var verbose: Bool

        public init(host: String = HBP.defaultHost,
                    port: UInt16 = HBP.defaultPort,
                    repeaterID: UInt32,
                    password: String,
                    repeaterInfo: RepeaterInfo = RepeaterInfo(callsign: "N0CALL"),
                    sendConfiguration: Bool = true,
                    verbose: Bool = false) {
            self.host = host
            self.port = port
            self.repeaterID = repeaterID
            self.password = password
            self.repeaterInfo = repeaterInfo
            self.sendConfiguration = sendConfiguration
            self.verbose = verbose
        }
    }

    /// 所有回调都在内部串行队列上触发，UI 侧需要自行切回主线程。
    public var onEvent: ((ClientEvent) -> Void)?

    private let config: Configuration
    private let queue = DispatchQueue(label: "org.pistar.brandmeister.hbp")

    private var connection: NWConnection?
    private var framer = HomebrewFramer()
    private var timer: DispatchSourceTimer?

    private var state: ClientState = .idle {
        didSet { if state != oldValue { emit(.stateChanged(state)) } }
    }

    private var wantsRun = false
    private var reconnectScheduled = false
    private var reconnectAttempt = 0
    private var handshakeAttempts = 0
    private var challenge: UInt32 = 0
    private var lastSend = Date.distantPast
    private var lastReceive = Date()

    public init(configuration: Configuration) {
        self.config = configuration
    }

    // MARK: - 生命周期

    public func start() {
        queue.async {
            guard !self.wantsRun else { return }
            self.wantsRun = true
            self.reconnectAttempt = 0
            self.open()
        }
    }

    public func stop() {
        queue.async {
            guard self.wantsRun else { return }
            self.wantsRun = false
            if self.state.isRunning { self.sendClose() }
            self.state = .closing
            self.queue.asyncAfter(deadline: .now() + 0.2) {
                self.teardownSocket()
                self.state = .idle
                self.log("已断开连接")
            }
        }
    }

    // MARK: - 连接

    private func open() {
        guard wantsRun else { return }
        teardownSocket()
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            emit(.error("端口无效: \(config.port)"))
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.connectionTimeout = 10
        }

        let connection = NWConnection(host: NWEndpoint.Host(config.host),
                                      port: port,
                                      using: parameters)
        self.connection = connection
        state = .connecting
        log("连接 \(config.host):\(config.port)")

        connection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }
        connection.start(queue: queue)
        startTimer()
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            log("TCP 已建立")
            framer.reset()
            handshakeAttempts = 0
            lastReceive = Date()
            receiveLoop()
            sendLogin()
            state = .loggingIn
        case .waiting(let error):
            log("连接等待: \(error.localizedDescription)")
        case .failed(let error):
            fail("连接失败: \(error.localizedDescription)")
        case .cancelled:
            if wantsRun { scheduleReconnect() }
        default:
            break
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lastReceive = Date()
                self.framer.append([UInt8](data))
                self.drainPackets()
            }
            if let error {
                self.fail("接收失败: \(error.localizedDescription)")
                return
            }
            if isComplete {
                self.fail("主站关闭了连接")
                return
            }
            self.receiveLoop()
        }
    }

    private func drainPackets() {
        while let packet = framer.next() {
            handle(packet)
        }
    }

    // MARK: - 收包处理

    private func handle(_ packet: HomebrewPacket) {
        switch packet {
        case .repeaterAck(let value):
            switch state {
            case .loggingIn:
                challenge = value
                sendAuth()
                state = .authenticating
            case .authenticating:
                if config.sendConfiguration {
                    sendConfig()
                    state = .configuring
                } else {
                    becomeRunning()
                }
            case .configuring:
                becomeRunning()
            default:
                break
            }

        case .masterPong:
            break   // lastReceive 已在接收回调刷新

        case .masterNak:
            switch state {
            case .loggingIn:
                fail("登录被拒绝：ID \(config.repeaterID) 不被主站接受")
            case .authenticating:
                fail("鉴权失败：Hotspot 密码错误")
            case .configuring:
                // 有些主站不接受 RPTC，不影响后续语音，按非致命处理。
                log("主站拒绝了配置报文，继续以 RUNNING 状态保活")
                becomeRunning()
            default:
                log("会话被主站标记，重新登录")
                sendLogin()
                state = .loggingIn
            }

        case .masterClosed:
            fail("主站主动断开 (MSTCL)")

        case .beacon:
            log("主站请求信标 (RPTSBKN)，本客户端不发送语音，忽略")

        case .dmrData(let packet):
            emit(.packet(packet))

        case .other(let prefix, let bytes):
            if config.verbose {
                log("未知报文 \(prefix) \(bytes.hexString)")
            }
        }
    }

    private func becomeRunning() {
        state = .running
        reconnectAttempt = 0
        handshakeAttempts = 0
        lastReceive = Date()
        log("登录完成，开始接收通话")
    }

    // MARK: - 发包

    private func sendLogin() {
        var bytes = HBP.login
        bytes += config.repeaterID.bigEndianBytes
        send(bytes, label: "RPTL")
    }

    private func sendAuth() {
        var bytes = HBP.auth
        bytes += config.repeaterID.bigEndianBytes
        bytes += SHA256Auth.digest(salt: challenge, password: config.password)
        send(bytes, label: "RPTK")
    }

    private func sendConfig() {
        send(config.repeaterInfo.encoded(repeaterID: config.repeaterID), label: "RPTC")
    }

    private func sendPing() {
        var bytes = HBP.ping
        bytes += config.repeaterID.bigEndianBytes
        send(bytes, label: "RPTPING", quiet: true)
    }

    private func sendClose() {
        var bytes = HBP.close
        bytes += config.repeaterID.bigEndianBytes
        send(bytes, label: "RPTCL")
    }

    private func send(_ bytes: [UInt8], label: String, quiet: Bool = false) {
        guard let connection else { return }
        lastSend = Date()
        if config.verbose || !quiet {
            log("→ \(label) (\(bytes.count) 字节)")
        }
        connection.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async { self.fail("发送 \(label) 失败: \(error.localizedDescription)") }
        })
    }

    // MARK: - 定时器

    private func startTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard wantsRun else { return }
        switch state {
        case .loggingIn, .authenticating, .configuring:
            guard Date().timeIntervalSince(lastSend) >= HBP.handshakeRetryInterval else { return }
            handshakeAttempts += 1
            if handshakeAttempts > HBP.maxHandshakeRetries {
                fail("握手超时：主站无响应")
                return
            }
            resendHandshake()

        case .running:
            if Date().timeIntervalSince(lastSend) >= HBP.pingInterval {
                sendPing()
            }
            if Date().timeIntervalSince(lastReceive) >= HBP.receiveTimeout {
                fail("心跳超时：\(Int(HBP.receiveTimeout))s 未收到主站数据")
            }

        default:
            break
        }
    }

    private func resendHandshake() {
        switch state {
        case .loggingIn: sendLogin()
        case .authenticating: sendAuth()
        case .configuring: sendConfig()
        default: break
        }
    }

    // MARK: - 失败与重连

    private func fail(_ reason: String) {
        log("✖ \(reason)")
        emit(.error(reason))
        teardownSocket()
        guard wantsRun else {
            state = .idle
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard wantsRun, !reconnectScheduled else { return }
        reconnectScheduled = true
        reconnectAttempt += 1
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt - 1)))
        state = .waitingToReconnect(attempt: reconnectAttempt)
        log("\(Int(delay)) 秒后重连（第 \(reconnectAttempt) 次）")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            guard self.wantsRun else { return }
            self.open()
        }
    }

    private func teardownSocket() {
        timer?.cancel()
        timer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        framer.reset()
    }

    // MARK: - 事件

    private func log(_ message: String) {
        emit(.log(message))
    }

    private func emit(_ event: ClientEvent) {
        onEvent?(event)
    }
}
