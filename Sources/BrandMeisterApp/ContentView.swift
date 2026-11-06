import BrandMeisterKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SessionViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(model.statusColor).frame(width: 9, height: 9)
                        Text(model.state.description).font(.subheadline)
                        Spacer()
                        Text(model.connected ? "会话已启动" : "未连接")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    connectionForm
                } header: {
                    Text("BrandMeister 连接")
                }

                Section("链路统计") {
                    statRow("DMRD 报文", "\(model.health.bursts)")
                    statRow("语音 burst", "\(model.health.voiceBursts)")
                    statRow("AMBE 块", "\(model.health.ambeBlocks)")
                    statRow("已解通话", "\(model.health.callsHeard)")
                }

                Section("当前通话") {
                    if model.activeCalls.isEmpty {
                        Text("暂无活动通话").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.activeCalls) { call in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TG/ID \(call.destinationID)  ←  \(call.sourceID)").font(.headline)
                                Text("TS\(call.slot) · \(call.isPrivate ? "个呼" : "组呼") · \(String(format: "%.1fs", call.duration)) · \(call.frameCount) 帧")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                }

                Section("最近结束") {
                    if model.history.isEmpty {
                        Text("暂无记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.history.prefix(10)) { call in
                            Text("\(String(format: "%.1fs", call.duration))  TG \(call.destinationID)  源 \(call.sourceID)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                Section {
                    if model.logs.isEmpty {
                        Text("等待连接事件…").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.logs.suffix(150).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    HStack {
                        Text("事件日志")
                        Spacer()
                        Text("\(model.logs.count) 条").foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pi-Star")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("DMR ID", text: $model.dmrID)
                .keyboardType(.numberPad).textContentType(.username)
                .disabled(model.connected)
            SecureField("BrandMeister Hotspot 密码", text: $model.password)
                .textContentType(.password).disabled(model.connected)
            TextField("主站地址", text: $model.host)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).disabled(model.connected)
            TextField("通话组过滤（例如 91,460）", text: $model.talkgroups)
                .keyboardType(.numbersAndPunctuation).disabled(model.connected)
            Toggle("音频输出", isOn: $model.audioEnabled).disabled(model.connected)
            Button { model.toggle() } label: {
                Label(model.connected ? "断开连接" : "连接 BrandMeister",
                      systemImage: model.connected ? "xmark.circle" : "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
