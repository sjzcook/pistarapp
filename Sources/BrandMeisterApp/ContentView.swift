import BrandMeisterKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SessionViewModel()

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            console
                .frame(minWidth: 460)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 左侧

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                connectionForm
                statistics
                activeCalls
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pi-Star · BrandMeister")
                .font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Circle()
                    .fill(model.statusColor)
                    .frame(width: 8, height: 8)
                Text(model.state.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField("DMR ID") {
                TextField("4601234", text: $model.dmrID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.connected)
            }
            labeledField("Hotspot 密码") {
                SecureField("BrandMeister 自助页面密码", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.connected)
            }
            labeledField("主站") {
                TextField("master.brandmeister.network", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.connected)
            }
            labeledField("通话组过滤") {
                TextField("留空表示全部，例如 91,460", text: $model.talkgroups)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.connected)
            }
            Toggle("音频输出", isOn: $model.audioEnabled)
                .toggleStyle(.switch)
                .disabled(model.connected)

            Button(model.connected ? "断开" : "连接") {
                model.toggle()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("链路统计")
                .font(.subheadline.weight(.semibold))
            statRow("DMRD 报文", "\(model.health.bursts)")
            statRow("语音 burst", "\(model.health.voiceBursts)")
            statRow("AMBE 块", "\(model.health.ambeBlocks)")
            statRow("已解通话", "\(model.health.callsHeard)")
        }
    }

    private var activeCalls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前通话")
                .font(.subheadline.weight(.semibold))

            if model.activeCalls.isEmpty {
                Text("暂无")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.activeCalls) { call in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TG/ID \(String(call.destinationID))  ←  \(String(call.sourceID))")
                            .font(.callout.weight(.medium))
                        Text("TS\(call.slot) · \(call.isPrivate ? "个呼" : "组呼") · \(String(format: "%.1fs", call.duration)) · \(call.frameCount) 帧")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !model.history.isEmpty {
                Divider().padding(.vertical, 4)
                Text("最近结束")
                    .font(.subheadline.weight(.semibold))
                ForEach(model.history.prefix(6)) { call in
                    Text("\(String(format: "%5.1fs", call.duration))  TG \(String(call.destinationID))  源 \(String(call.sourceID))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 右侧

    private var console: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("事件日志")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.logs.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.logs.indices), id: \.self) { index in
                        Text(model.logs[index])
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    // MARK: - 小组件

    private func labeledField<Content: View>(_ title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}
