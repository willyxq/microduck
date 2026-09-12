import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                topbar
                Group {
                    switch model.screen {
                    case .discover: DiscoverView()
                    case .pin: PinView()
                    case .app:
                        switch model.tab {
                        case .home: HomeView()
                        case .interact: InteractView()
                        case .models: ModelsView()
                        case .settings: SettingsView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if model.screen == .app {
                TabBar()
            }
            if !model.toast.isEmpty {
                Text(model.toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.17, green: 0.16, blue: 0.15))
                    .clipShape(Capsule())
                    .padding(.bottom, model.screen == .app ? 92 : 28)
                    .transition(.opacity)
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.toast)
        .animation(.easeInOut(duration: 0.15), value: model.screen)
    }

    private var topbar: some View {
        HStack {
            Text("9:41").font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("模拟鸭子")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .foregroundStyle(Palette.ink)
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(model.tab == tab ? Palette.ink : Palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.testID)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Palette.card.opacity(0.93))
        .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("第一层 · 现场管理员")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Text("附近的鸭子")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                Text("模拟模式不扫蓝牙。真鸭子到了，同一套调用改走 BLE。")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                Button(action: model.openDuck) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("duck-sim").font(.system(size: 16, weight: .bold))
                            Text("SIM-0001 · ws://127.0.0.1:17432")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text("›").font(.system(size: 22)).foregroundStyle(Palette.muted)
                    }
                    .padding(18)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.06), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("duck-sim")
                Text("需要先在本机运行 scripts/duck-app-sim up。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.43, green: 0.33, blue: 0.06))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 0.973, blue: 0.910))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !model.error.isEmpty {
                    Text(model.error).font(.system(size: 14)).foregroundStyle(Palette.red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .foregroundStyle(Palette.ink)
        }
    }
}

struct PinView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接 duck-sim")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            Text("输入 PIN")
                .font(.system(size: 34, weight: .bold, design: .serif))
            Text("出厂 PIN 是 000000，和真鸭子一样写在仓库里。")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
            TextField("000000", text: $model.pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .medium).monospacedDigit())
                .padding(.vertical, 14)
                .frame(maxWidth: 220)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
                .focused($pinFocused)
                .accessibilityIdentifier("pin-input")
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Button {
                Task { await model.authenticate() }
            } label: {
                Text("认证")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color(red: 0.23, green: 0.16, blue: 0))
                    .background(Palette.duck)
                    .clipShape(Capsule())
            }
            .disabled(model.busy)
            .accessibilityIdentifier("pin-submit")
            if !model.error.isEmpty {
                Text(model.error).font(.system(size: 14)).foregroundStyle(Palette.red)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .foregroundStyle(Palette.ink)
        .onAppear { pinFocused = true }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.duckName)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                        Text("第一层 · 基础控制")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Chip(text: "现场连接", kind: .ok)
                }
                VStack(spacing: 8) {
                    Text("现场管理员模式")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text(model.healthTitle)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    DuckShape(size: 128)
                    HStack(spacing: 10) {
                        stat(model.batteryLabel, "电池")
                        stat(model.wifiLabel, "Wi-Fi")
                    }
                }
                .frame(maxWidth: .infinity)
                .modifier(Card())
                Button { model.tab = .models } label: {
                    row("行走模型有新版本", "daemon 0.10.0 → 0.11.0 · 模拟环境不下载", trailing: "查看")
                }
                .buttonStyle(.plain)
                Button { model.tab = .interact } label: {
                    row("去互动", "看画面、停止、坐下或叫一声", trailing: "›")
                }
                .buttonStyle(.plain)
                Text("先可靠，再聪明 · 无厂商控制云")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 110)
            .foregroundStyle(Palette.ink)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold))
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ title: String, _ sub: String, trailing: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(sub).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(trailing)
                .font(.system(size: trailing == "›" ? 22 : 14, weight: .semibold))
                .padding(.horizontal, trailing == "›" ? 0 : 12)
                .padding(.vertical, trailing == "›" ? 0 : 8)
                .background(trailing == "›" ? Color.clear : .white)
                .clipShape(Capsule())
        }
        .padding(18)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 6)
    }
}

struct InteractView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("互动").font(.system(size: 28, weight: .bold, design: .serif))
                    Spacer()
                    Chip(text: "基础控制")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L1Copy.cameraKicker)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text(L1Copy.cameraTitle)
                        .font(.system(size: 16, weight: .bold))
                    Text(L1Copy.cameraSub)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.847, green: 0.788, blue: 0.643), Color(red: 0.796, green: 0.710, blue: 0.541)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VStack {
                            Spacer()
                            Color(red: 0.906, green: 0.843, blue: 0.690)
                                .frame(height: 80)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 80, topTrailingRadius: 80))
                        }
                        DuckShape(size: 88)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .modifier(Card())
                .accessibilityIdentifier("camera-placeholder")
                Button {
                    model.refuseMotion(L1Copy.stop)
                } label: {
                    Text("立即停止")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Palette.red)
                        .background(.white)
                        .overlay(Capsule().stroke(Color(red: 0.953, green: 0.753, blue: 0.753), lineWidth: 1.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stop")
                Text("基础互动")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                HStack(spacing: 12) {
                    action("坐下 / 站起", id: "sit")
                    action("叫一声", id: "quack")
                }
                Text("手动驾驶 · 调试能力")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 6)
                Text("等待低延迟 teleop 通道\n运动控制不经 BLE")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.70, green: 0.68, blue: 0.64))
                    .multilineTextAlignment(.center)
                    .frame(width: 168, height: 168)
                    .background(Color(red: 0.953, green: 0.933, blue: 0.894))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 110)
            .foregroundStyle(Palette.ink)
        }
    }

    private func action(_ title: String, id: String) -> some View {
        Button {
            model.refuseMotion(L1Copy.sit)
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("模型").font(.system(size: 28, weight: .bold, design: .serif))
                    Spacer()
                    Chip(text: string(model.net["ssid"]) == nil ? "未联网" : "鸭子已联网", kind: .ok)
                }
                Text("第一层 · 能力底座")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("行走 Walk").font(.system(size: 16, weight: .bold))
                            Text("当前 v\(model.installedVersion)")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Chip(text: "有更新", kind: .warn)
                    }
                    Text("v0.11.0 · 模拟环境只报告，不下载制品")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                    Button {
                        Task { await model.applyUpdate() }
                    } label: {
                        Text("更新")
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color(red: 0.23, green: 0.16, blue: 0))
                            .background(Palette.duck)
                            .clipShape(Capsule())
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("apply-update")
                    Button {
                        model.rollbackDraft = true
                    } label: {
                        Text("回到上一版本")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Palette.ink)
                            .background(.white)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    .accessibilityIdentifier("rollback")
                }
                .modifier(Card())
                if model.rollbackDraft {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("确认回退").font(.system(size: 16, weight: .bold))
                        Text("回退目标：已安装 v\(model.installedVersion)。不会恢复出厂。")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                        Button {
                            model.rollbackDraft = false
                            Task { await model.rollbackUpdate() }
                        } label: {
                            Text("确认回退")
                                .font(.system(size: 17, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(Color(red: 0.23, green: 0.16, blue: 0))
                                .background(Palette.duck)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busy)
                        .accessibilityIdentifier("rollback-confirm")
                        Button {
                            model.rollbackDraft = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rollback-cancel")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(Card())
                    .accessibilityIdentifier("rollback-confirm-card")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("升级到第二层还差什么？").font(.system(size: 16, weight: .bold))
                    Text("5 个高级意图 · 成功率 90% · 安全验收。现在不要做意图墙。")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Card())
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 110)
            .foregroundStyle(Palette.ink)
        }
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置").font(.system(size: 28, weight: .bold, design: .serif))
                Text("\(model.serial) · \(model.duckName)")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接").font(.system(size: 16, weight: .bold))
                    Text("传输：MICRODUCK_TRANSPORT=\(DuckRpc.transport) · 真鸭子到了改 ble，页面和调用名不改")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                    Text(model.healthOK ? "健康：控制环在跑" : "健康：\(model.healthTitle)")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Card())
                HStack {
                    Text("Wi-Fi").font(.system(size: 22, weight: .bold, design: .serif))
                    Spacer()
                    Button {
                        Task { await model.scanWifi() }
                    } label: {
                        Text("扫描")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .background(.white)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wifi-scan")
                }
                if model.networks.isEmpty {
                    Text("点扫描，FakeNet 会给出 Pollen 和 Cafe。")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
                ForEach(model.networks) { net in
                    Button {
                        Task { await model.selectWifi(net) }
                    } label: {
                        HStack {
                            Text(net.ssid).font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("\(net.isOpen ? "开放" : "WPA") · \(String(describing: net.signal))")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wifi-\(net.ssid)")
                }
                if let ssid = model.wifiDraftSSID {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("加入 \(ssid)").font(.system(size: 16, weight: .bold))
                        Text("错密码必须显示是密码问题，不能说网络没了。")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            TextField("密码", text: $model.wifiDraftPSK)
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 48)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Palette.line, lineWidth: 1)
                                )
                                .accessibilityIdentifier("wifi-password")
                            Button {
                                Task { await model.joinDraft() }
                            } label: {
                                Text("加入")
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 48)
                                    .foregroundStyle(Color(red: 0.23, green: 0.16, blue: 0))
                                    .background(Palette.duck)
                                    .clipShape(Capsule())
                            }
                            .disabled(model.busy)
                            .accessibilityIdentifier("wifi-join")
                        }
                    }
                    .modifier(Card())
                }
                if !model.error.isEmpty {
                    Text(model.error)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.red)
                        .accessibilityIdentifier("error")
                }
                Text("Pollen 的密码是 correct-key。其他密码会返回 BadKey，App 必须说是密码问题。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.43, green: 0.33, blue: 0.06))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 0.973, blue: 0.910))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 110)
            .foregroundStyle(Palette.ink)
        }
    }
}
