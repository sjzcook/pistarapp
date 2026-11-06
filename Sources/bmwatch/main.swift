import BrandMeisterKit
import Darwin
import Foundation

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

private func emitLine(_ line: String) {
    let stamp = timeFormatter.string(from: Date())
    FileHandle.standardOutput.write(Data("[\(stamp)] \(line)\n".utf8))
}

private func usage() -> Never {
    let text = """
    bmwatch — 以 Pi-Star 的 Homebrew 协议连接 BrandMeister 并打印通话

    用法:
      bmwatch --id <DMR ID> --password <Hotspot密码> [选项]

    选项:
      --id <n>          热点/中继的 DMR ID（登录用，必填）
      --password <s>    BrandMeister 自助页面的 Hotspot 密码（必填，或用环境变量 BM_PASSWORD）
      --host <h>        主站地址，默认 \(HBP.defaultHost)
      --port <n>        主站端口，默认 \(HBP.defaultPort)
      --tg <a,b,c>      只显示这些通话组，留空表示全部
      --callsign <s>    RPTC 上报的呼号
      --no-config       不发送 RPTC 配置报文
      --audio           打开音频输出（需自行接入 AMBE 解码器，见 README）
      --verbose         打印心跳与原始报文

    示例:
      bmwatch --id 4601234 --password ****** --tg 91,460
    """
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
    exit(2)
}

// MARK: - 参数解析

var repeaterID: UInt32?
var password = ProcessInfo.processInfo.environment["BM_PASSWORD"]
var host = HBP.defaultHost
var port = HBP.defaultPort
var watchTalkgroups = Set<UInt32>()
var callsign = "N0CALL"
var sendConfig = true
var audioEnabled = false
var verbose = false

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let flag = arguments[index]
    func value() -> String {
        index += 1
        guard index < arguments.count else { usage() }
        return arguments[index]
    }
    switch flag {
    case "--id": repeaterID = UInt32(value())
    case "--password": password = value()
    case "--host": host = value()
    case "--port":
        guard let parsed = UInt16(value()) else { usage() }
        port = parsed
    case "--tg":
        for item in value().split(separator: ",") {
            let text = String(item).trimmingCharacters(in: .whitespaces)
            if let tg = UInt32(text) { watchTalkgroups.insert(tg) }
        }
    case "--callsign": callsign = value()
    case "--no-config": sendConfig = false
    case "--audio": audioEnabled = true
    case "--verbose", "-v": verbose = true
    case "--help", "-h": usage()
    default:
        emitLine("未知参数: \(flag)")
        usage()
    }
    index += 1
}

guard let dmrID = repeaterID, dmrID > 0 else {
    emitLine("缺少 --id")
    usage()
}
guard let hotspotPassword = password, !hotspotPassword.isEmpty else {
    emitLine("缺少 --password（或设置环境变量 BM_PASSWORD）")
    usage()
}

// MARK: - 会话

var config = HomebrewClient.Configuration(repeaterID: dmrID,
                                         password: hotspotPassword,
                                         repeaterInfo: RepeaterInfo(callsign: callsign),
                                         sendConfiguration: sendConfig,
                                         verbose: verbose)
config.host = host
config.port = port

let session = BrandMeisterSession(options: .init(client: config,
                                                 watchTalkgroups: watchTalkgroups,
                                                 audioEnabled: audioEnabled))

session.onEvent = { event in
    switch event {
    case .state(let state):
        emitLine("● \(state.description)")
    case .log(let message):
        emitLine("· \(message)")
    case .error(let message):
        emitLine("✖ \(message)")
    case .callStarted(let call):
        let kind = call.isPrivate ? "个呼" : "组呼"
        emitLine("▶ TS\(call.slot) \(kind) TG/ID \(call.destinationID) ← \(call.sourceID)")
    case .callEnded(let call):
        emitLine(String(format: "■ 结束 TG %u  源 %u  %.1fs  %d 帧",
                     call.destinationID, call.sourceID, call.duration, call.frameCount))
    case .health(let health):
        if verbose {
            emitLine("… burst \(health.bursts) 语音 \(health.voiceBursts) AMBE \(health.ambeBlocks) 通话 \(health.callsHeard)")
        }
    }
}

let tgText = watchTalkgroups.isEmpty
    ? "全部通话组"
    : watchTalkgroups.sorted().map { String($0) }.joined(separator: ",")
emitLine("连接 \(host):\(port)  ID=\(dmrID)  监听=\(tgText)")
session.start()

RunLoop.main.run()
