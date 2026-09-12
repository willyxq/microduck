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

struct DuckSkill: Identifiable {
    var id: String
    var title: String
    var blurb: String
    var kind: String
    var body: String
    var ready: Bool
    var installed: Bool
    var available: Bool
    var removable: Bool
    var active: Bool
    var source: String

    static func parse(_ raw: [String: Any]) -> DuckSkill? {
        guard let id = raw["id"] as? String, let title = raw["title"] as? String else { return nil }
        return DuckSkill(
            id: id,
            title: title,
            blurb: raw["blurb"] as? String ?? "",
            kind: raw["kind"] as? String ?? "",
            body: raw["body"] as? String ?? "walk",
            ready: raw["ready"] as? Bool ?? false,
            installed: raw["installed"] as? Bool ?? false,
            available: raw["available"] as? Bool ?? false,
            removable: raw["removable"] as? Bool ?? false,
            active: raw["active"] as? Bool ?? false,
            source: raw["source"] as? String ?? ""
        )
    }
}

struct WifiNetwork: Identifiable {
    var id: String { ssid }
    var ssid: String
    var security: String
    var signal: Any
    var isOpen: Bool { security == "open" }
}

enum L1Copy {
    static let stop = "立即停止不走 BLE。真急停是物理按钮；松手停靠 teleop 死人手。"
    static let sit = "坐下 / 叫一声要局域网控制通道，不能经 BLE 下发。"
    static let sitLan = "已切换坐下 / 站起（局域网，不经 BLE）"
    static let quackLan = "叫了一声（局域网，不经 BLE）"
    static let stopLan = "已停止（局域网控制通道，仍不是物理急停）"
    static let apply = "模拟环境不下载模型。真鸭子上由它自己的 Wi-Fi 拉签名包。"
    static let rollback = "模拟环境不切换已安装版本。真鸭子上回退已安装版本，不经 BLE 传文件。"
    static let cameraKicker = "摄像头"
    static let cameraTitle = "现在没有直播"
    static let cameraSub = "画面要等局域网 / WebRTC。这里不是假视频。"
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
    @Published var rollbackDraft = false
    @Published var lanReady = false
    @Published var cameraLive = false
    @Published var skills: [DuckSkill] = []
    @Published var locomotion = "walk"
    @Published var driveVx = 0.0
    @Published var driveVyaw = 0.0
    @Published var holdDir = ""
    private var drivePulse: Task<Void, Never>?

    var driving: Bool { abs(driveVx) + abs(driveVyaw) > 0.02 }

    var driveLabel: String {
        if !driving { return "待机" }
        var bits: [String] = []
        if driveVx > 0.02 { bits.append("前进") }
        if driveVx < -0.02 { bits.append("后退") }
        if driveVyaw > 0.05 { bits.append("左转") }
        if driveVyaw < -0.05 { bits.append("右转") }
        return bits.isEmpty ? "待机" : bits.joined(separator: " · ")
    }

    let rpc = DuckRpc()
    let lan = DuckRpc(url: DuckRpc.lanURL)

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
            haltDrive()
            tab = .home
            return true
        case "nav-interact":
            tab = .interact
            Task {
                await probeCamera()
                await probeSkills()
            }
            return true
        case "nav-models":
            haltDrive()
            tab = .models
            Task { await probeSkills() }
            return true
        case "nav-settings":
            haltDrive()
            tab = .settings
            return true
        case "drive-fwd":
            holdDrive(dir: "drive-fwd", vx: 0.3, vyaw: 0)
            return true
        case "drive-back":
            holdDrive(dir: "drive-back", vx: -0.3, vyaw: 0)
            return true
        case "drive-left":
            holdDrive(dir: "drive-left", vx: 0, vyaw: 1.5)
            return true
        case "drive-right":
            holdDrive(dir: "drive-right", vx: 0, vyaw: -1.5)
            return true
        case "drive-halt":
            haltDrive()
            return true
        case "stop":
            haltDrive()
            Task { await lanOrToast("robot.stop", [:], L1Copy.stopLan, L1Copy.stop) }
            return true
        case "sit":
            Task { await lanOrToast("robot.do", ["skill": "sit_toggle"], L1Copy.sitLan, L1Copy.sit) }
            return true
        case "quack":
            Task { await lanOrToast("robot.sound", [:], L1Copy.quackLan, L1Copy.sit) }
            return true
        case "apply-update":
            Task { await applyUpdate() }
            return true
        case "rollback":
            rollbackDraft = true
            return true
        case "rollback-cancel":
            rollbackDraft = false
            return true
        case "rollback-confirm":
            rollbackDraft = false
            Task { await rollbackUpdate() }
            return true
        case "wifi-scan":
            Task { await scanWifi() }
            return true
        case "wifi-join":
            Task { await joinDraft() }
            return true
        default:
            if id.hasPrefix("uninstall-") {
                let skill = String(id.dropFirst("uninstall-".count))
                Task { await uninstallSkill(skill) }
                return true
            }
            if id.hasPrefix("install-") {
                let skill = String(id.dropFirst("install-".count))
                Task { await installSkill(skill) }
                return true
            }
            if id.hasPrefix("skill-") {
                let skill = String(id.dropFirst("skill-".count))
                Task { await doSkill(skill) }
                return true
            }
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
            await connectLan()
            screen = .app
            tab = .home
        }
    }

    func probeCamera() async {
        guard let url = URL(string: "\(DuckRpc.cameraStill)?t=\(Int(Date().timeIntervalSince1970 * 1000))") else {
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                cameraLive = true
            }
        } catch {
            /* LAN hello is independent; keep whatever cameraLive already is if the still is late */
        }
    }

    func connectLan() async {
        do {
            try await lan.connect()
            _ = try await lan.hello()
            lanReady = true
            if let cam = try? await lan.call("camera.info") as? [String: Any] {
                cameraLive = bool(cam["live"])
            }
        } catch {
            lanReady = false
        }
        await probeCamera()
        await probeSkills()
    }

    func probeSkills() async {
        guard lanReady else {
            skills = []
            return
        }
        guard let out = try? await lan.call("skill.list") as? [String: Any] else { return }
        locomotion = string(out["locomotion"]) ?? "walk"
        let rows = out["skills"] as? [[String: Any]] ?? []
        skills = rows.compactMap(DuckSkill.parse)
    }

    func installSkill(_ id: String) async {
        guard lanReady else {
            showToast("先开身体孪生，再下载能力")
            return
        }
        do {
            _ = try await lan.call("skill.install", params: ["id": id])
            await probeSkills()
            let title = skills.first(where: { $0.id == id })?.title ?? id
            showToast(id == "all" ? "已启用全部动作能力" : "已启用「\(title)」")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func uninstallSkill(_ id: String) async {
        guard lanReady else {
            showToast("先开身体孪生，再卸载能力")
            return
        }
        do {
            _ = try await lan.call("skill.uninstall", params: ["id": id])
            await probeSkills()
            let title = skills.first(where: { $0.id == id })?.title ?? id
            showToast(id == "all" ? "已卸载下载的能力" : "已卸载「\(title)」")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func doSkill(_ id: String) async {
        let title = skills.first(where: { $0.id == id })?.title ?? id
        await lanOrToast("robot.do", ["skill": id], "\(title)（局域网，不经 BLE）", "这个动作要先下载模型")
        await probeSkills()
    }

    func notifyMove(vx: Double, vy: Double = 0, vyaw: Double) {
        driveVx = vx
        driveVyaw = vyaw
        guard lanReady else { return }
        lan.notify("robot.move", params: ["vx": vx, "vy": vy, "vyaw": vyaw])
        pulseDrive()
    }

    func holdDrive(dir: String, vx: Double, vyaw: Double) {
        holdDir = dir
        notifyMove(vx: vx, vyaw: vyaw)
    }

    func haltDrive() {
        drivePulse?.cancel()
        drivePulse = nil
        driveVx = 0
        driveVyaw = 0
        holdDir = ""
        guard lanReady else { return }
        lan.notify("robot.move", params: ["vx": 0, "vy": 0, "vyaw": 0])
    }

    private func pulseDrive() {
        guard drivePulse == nil else { return }
        drivePulse = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.driving else { continue }
                self.lan.notify("robot.move", params: ["vx": self.driveVx, "vy": 0, "vyaw": self.driveVyaw])
            }
        }
    }

    func lanOrToast(_ method: String, _ params: [String: Any], _ ok: String, _ fallback: String) async {
        guard lanReady else {
            refuseMotion(fallback)
            return
        }
        do {
            _ = try await lan.call(method, params: params)
            showToast(ok)
        } catch {
            showToast(error.localizedDescription)
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
                throw DuckRpcError.remote(L1Copy.apply)
            }
        }
    }

    func rollbackUpdate() async {
        await withBusy {
            do {
                _ = try await rpc.call("update.rollback", params: ["component": "daemon"])
            } catch {
                throw DuckRpcError.remote(L1Copy.rollback)
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
