import Foundation
import SwiftUI

enum Screen {
    case discover, pin, app
}

enum Tab: String, CaseIterable, Identifiable {
    case home, interact, models, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .interact: "互动"
        case .models: "模型"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .interact: "dot.radiowaves.left.and.right"
        case .models: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }

    var testID: String { "nav-\(rawValue)" }
}

struct WifiNetwork: Identifiable {
    var id: String { ssid }
    var ssid: String
    var security: String
    var signal: Any
    var isOpen: Bool { security == "open" }
}

enum HarnessTarget {
    static weak var model: AppModel?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .discover
    @Published var tab: Tab = .home
    @Published var pin = ""
    @Published var toast = ""
    @Published var busy = false
    @Published var error = ""
    @Published var info: [String: Any] = [:]
    @Published var health: [String: Any] = [:]
    @Published var net: [String: Any] = [:]
    @Published var networks: [WifiNetwork] = []
    @Published var installedVersion = "0.10.0"
    @Published var wifiDraftSSID: String?
    @Published var wifiDraftPSK = ""

    let rpc = DuckRpc()

    init() {
        HarnessTarget.model = self
    }

    /// Same actions as the on-screen buttons. Used by the loopback tap bridge.
    @discardableResult
    func performHarnessAction(_ id: String) -> Bool {
        switch id {
        case "duck-sim":
            openDuck()
            return true
        case "pin-input", "wifi-password":
            return true
        case "pin-submit":
            Task { await authenticate() }
            return true
        case "nav-home":
            tab = .home
            return true
        case "nav-interact":
            tab = .interact
            return true
        case "nav-models":
            tab = .models
            return true
        case "nav-settings":
            tab = .settings
            return true
        case "stop":
            refuseMotion("立即停止不走 BLE。真急停是物理按钮；松手停靠 teleop 死人手。")
            return true
        case "sit":
            refuseMotion("坐下 / 叫一声要局域网控制通道，不能经 BLE 下发。")
            return true
        case "quack":
            refuseMotion("坐下 / 叫一声要局域网控制通道，不能经 BLE 下发。")
            return true
        case "apply-update":
            Task { await applyUpdate() }
            return true
        case "wifi-scan":
            Task { await scanWifi() }
            return true
        case "wifi-join":
            Task { await joinDraft() }
            return true
        default:
            if id.hasPrefix("wifi-"), id != "wifi-scan", id != "wifi-join", id != "wifi-password" {
                let ssid = String(id.dropFirst("wifi-".count))
                if let net = networks.first(where: { $0.ssid == ssid }) {
                    Task { await selectWifi(net) }
                    return true
                }
            }
            return false
        }
    }

    var duckName: String { string(info["name"]) ?? "duck-sim" }
    var serial: String { string(info["serial"]) ?? "SIM-0001" }

    var batteryLabel: String {
        if let battery = health["battery"] as? [String: Any],
           let pct = number(battery["percent"])
        {
            return "\(Int(pct.rounded()))%"
        }
        return "—"
    }

    var wifiLabel: String {
        if let ssid = string(net["ssid"]), !ssid.isEmpty { return ssid }
        if string(net["state"]) == "disconnected" { return "未联网" }
        if net.isEmpty { return "未读到" }
        return string(net["state"]) ?? "未知"
    }

    var healthTitle: String {
        if health.isEmpty { return "正在读取" }
        if bool(health["healthy"]) { return "一切正常" }
        return string(health["reason"]) ?? "需要处理"
    }

    var healthOK: Bool { bool(health["healthy"]) }

    func showToast(_ message: String) {
        toast = message
        let captured = message
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toast == captured { toast = "" }
        }
    }

    func openDuck() {
        error = ""
        screen = .pin
    }

    func authenticate() async {
        await withBusy {
            let value = pin.isEmpty ? "000000" : pin
            pin = value
            try await rpc.connect()
            _ = try await rpc.hello()
            let auth = try await rpc.authenticate(pin: value)
            if !auth.authenticated {
                throw DuckRpcError.remote("PIN 不对，还剩 \(auth.attempts_remaining ?? 0) 次")
            }
            if let info = try await rpc.call("system.info") as? [String: Any] {
                self.info = info
            }
            await refreshStatus()
            screen = .app
            tab = .home
        }
    }

    func refreshStatus() async {
        if let v = try? await rpc.call("system.info") as? [String: Any] { info = v }
        do {
            if let v = try await rpc.call("robot.health") as? [String: Any] {
                health = v
            }
        } catch {
            health = ["healthy": false, "reason": error.localizedDescription]
        }
        if let v = try? await rpc.call("net.status") as? [String: Any] { net = v }
        if let v = try? await rpc.call("update.listInstalled", params: ["component": "daemon"]) {
            if let list = v as? [[String: Any]], let first = list.first {
                installedVersion = string(first["version"]) ?? installedVersion
            } else if let dict = v as? [String: Any],
                      let list = dict["versions"] as? [[String: Any]],
                      let first = list.first
            {
                installedVersion = string(first["version"]) ?? installedVersion
            }
        }
    }

    func scanWifi() async {
        await withBusy {
            let raw = try await rpc.call("net.scan")
            let list: [[String: Any]]
            if let dict = raw as? [String: Any], let networks = dict["networks"] as? [[String: Any]] {
                list = networks
            } else {
                list = []
            }
            networks = list.map { item in
                WifiNetwork(
                    ssid: string(item["ssid"]) ?? "",
                    security: string(item["security"]) ?? "",
                    signal: item["signal"] ?? 0
                )
            }
        }
    }

    func selectWifi(_ network: WifiNetwork) async {
        if network.isOpen {
            wifiDraftSSID = nil
            await joinWifi(ssid: network.ssid, psk: nil)
            return
        }
        wifiDraftSSID = network.ssid
        wifiDraftPSK = ""
        error = ""
    }

    func joinDraft() async {
        guard let ssid = wifiDraftSSID else { return }
        await joinWifi(ssid: ssid, psk: wifiDraftPSK)
    }

    func joinWifi(ssid: String, psk: String?) async {
        await withBusy {
            var params: [String: Any] = ["ssid": ssid]
            if let psk { params["psk"] = psk }
            let raw = try await rpc.call("net.connect", params: params)
            let result = raw as? [String: Any] ?? [:]
            if string(result["outcome"]) == "failed" {
                if string(result["reason"]) == "bad_key" {
                    throw DuckRpcError.remote("密码不对（BadKey），不是网络消失了")
                }
                throw DuckRpcError.remote(string(result["reason"]) ?? "加入失败")
            }
            showToast("已加入 \(ssid)")
            await refreshStatus()
        }
    }

    func refuseMotion(_ message: String) {
        showToast(message)
    }

    func applyUpdate() async {
        await withBusy {
            do {
                _ = try await rpc.call("update.apply", params: ["component": "daemon"])
            } catch {
                throw DuckRpcError.remote("模拟环境不下载模型。真鸭子上由它自己的 Wi-Fi 拉签名包。")
            }
        }
    }

    private func withBusy(_ work: () async throws -> Void) async {
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await work()
        } catch {
            self.error = error.localizedDescription
            showToast(self.error)
        }
    }

    private func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if value is NSNull { return nil }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private func bool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }
}
