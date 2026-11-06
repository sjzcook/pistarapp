import Foundation

/// Homebrew Repeater Protocol（MMDVM/HBP），也就是 Pi-Star 里
/// MMDVMHost / DMRGateway 用来和 BrandMeister 主站通话的那套协议。
///
/// 与 Pi-Star 的对应关系：
/// - `HomebrewClient`       ≈ `CDMRNetwork`（状态机 + 定时器）
/// - `DMRDataPacket`        ≈ `CDMRData` + `DMRDefines.h`
/// - `CallTracker`          ≈ `CDMRDMRSlot` / 通话生命周期
public enum HBP {
    /// BrandMeister 主站地址（按服务器也可用 bm<国家码>.brandmeister.network）。
    public static let defaultHost = "master.brandmeister.network"
    /// Homebrew 协议固定端口。
    public static let defaultPort: UInt16 = 62031

    // 客户端 → 主站
    static let login = Array("RPTL".utf8)        // 8 字节
    static let auth = Array("RPTK".utf8)         // 40 字节
    static let config = Array("RPTC".utf8)       // 302 字节
    static let ping = Array("RPTPING".utf8)      // 11 字节
    static let close = Array("RPTCL".utf8)       // 9 字节
    static let data = Array("DMRD".utf8)         // 55 字节

    // 主站 → 客户端
    static let ack = "RPTACK"
    static let pong = "MSTPONG"
    static let nak = "MSTNAK"
    static let closed = "MSTCL"
    static let beacon = "RPTSBKN"

    /// DMRD 数据包长度。
    public static let dataPacketLength = 55
    /// DMR 负载长度（3 个 72bit 声码器块 + 同步/时隙类型）。
    public static let payloadLength = 33
    /// RPTC 配置负载长度。
    public static let configPayloadLength = 302

    /// 保活间隔：Pi-Star 的 DMRGateway 每 5 秒发一次 RPTPING。
    public static let pingInterval: TimeInterval = 5
    /// 握手阶段重发间隔（1 秒，最多 10 次，与 CTimer(1000, 10) 一致）。
    public static let handshakeRetryInterval: TimeInterval = 1
    public static let maxHandshakeRetries = 10
    /// 60 秒收不到任何主站数据即判定掉线。
    public static let receiveTimeout: TimeInterval = 60
}

/// 客户端状态机，与 DMRGateway 的 STATUS 枚举一一对应。
public enum ClientState: Equatable, CustomStringConvertible {
    case idle
    case connecting
    case loggingIn          // 已发 RPTL，等 RPTACK
    case authenticating     // 已发 RPTK，等 RPTACK
    case configuring        // 已发 RPTC，等 RPTACK
    case running            // 握手完成，进入保活
    case closing
    case waitingToReconnect(attempt: Int)

    public var description: String {
        switch self {
        case .idle: return "空闲"
        case .connecting: return "建立 TCP 连接"
        case .loggingIn: return "登录中 (RPTL)"
        case .authenticating: return "鉴权中 (RPTK)"
        case .configuring: return "上报配置 (RPTC)"
        case .running: return "已连接 RUNNING"
        case .closing: return "断开中"
        case .waitingToReconnect(let attempt): return "等待重连 #\(attempt)"
        }
    }

    public var isRunning: Bool { self == .running }
}
