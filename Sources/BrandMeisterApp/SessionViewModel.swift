import BrandMeisterKit
import Foundation
import SwiftUI

final class SessionViewModel: ObservableObject {
    @Published private(set) var state: ClientState = .idle
    @Published private(set) var activeCalls: [CallSession] = []
    @Published private(set) var history: [CallSummary] = []
    @Published private(set) var logs: [String] = []
    @Published private(set) var health = SessionHealth()
    @Published private(set) var connected = false

    @Published var host = HBP.defaultHost
    @Published var dmrID = ""
    @Published var password = ""
    @Published var talkgroups = ""
    @Published var audioEnabled = false

    private var session: BrandMeisterSession?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var statusColor: Color {
        switch state {
        case .running: return .green
        case .idle: return .gray
        case .waitingToReconnect: return .orange
        default: return .yellow
        }
    }

    func toggle() {
        if connected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        guard let id = UInt32(dmrID.trimmingCharacters(in: .whitespaces)), id > 0 else {
            appendLog("DMR ID 无效")
            return
        }
        guard !password.isEmpty else {
            appendLog("请填写 Hotspot 密码")
            return
        }

        let groups = Set(talkgroups
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { UInt32(String($0).trimmingCharacters(in: .whitespaces)) })

        var config = HomebrewClient.Configuration(repeaterID: id,
                                                 password: password,
                                                 repeaterInfo: RepeaterInfo(callsign: "N0CALL"),
                                                 verbose: true)
        config.host = host.trimmingCharacters(in: .whitespaces)

        let session = BrandMeisterSession(options: .init(client: config,
                                                         watchTalkgroups: groups,
                                                         audioEnabled: audioEnabled))
        session.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        self.session = session
        connected = true
        session.start()
    }

    func disconnect() {
        session?.stop()
        session = nil
        connected = false
        activeCalls = []
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .state(let newState):
            state = newState
            appendLog(newState.description)

        case .callStarted(let call):
            activeCalls.removeAll { $0.id == call.id }
            activeCalls.insert(call, at: 0)
            appendLog("起呼 TS\(call.slot) \(call.isPrivate ? "个呼" : "组呼") \(call.destinationID) ← \(call.sourceID)")

        case .callEnded(let summary):
            activeCalls.removeAll { $0.id == summary.id }
            history.insert(summary, at: 0)
            if history.count > 60 { history.removeLast(history.count - 60) }
            appendLog(String(format: "结束 %u  %.1fs  %d 帧",
                             summary.destinationID, summary.duration, summary.frameCount))

        case .log(let message):
            appendLog(message)

        case .error(let message):
            appendLog("✖ \(message)")

        case .health(let snapshot):
            health = snapshot
        }
    }

    private func appendLog(_ message: String) {
        logs.append("\(timeFormatter.string(from: Date()))  \(message)")
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }
}
