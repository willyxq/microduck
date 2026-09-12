import Darwin
import Foundation
import UIKit

/// Loopback tap bridge for harness. iOS Simulator shares 127.0.0.1 with the Mac,
/// so `curl http://127.0.0.1:17433/tap?id=duck-sim` is a real hit-test tap.
/// Laptop / simulator only — bound to IPv4 loopback.
enum TapBridge {
    static let port: UInt16 = 17433
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        Thread.detachNewThread {
            serve()
        }
        NSLog("TapBridge http://127.0.0.1:%u", port)
    }

    private static func serve() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindOk = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOk == 0, listen(fd, 8) == 0 else {
            close(fd)
            NSLog("TapBridge bind/listen failed: %d", errno)
            return
        }
        while true {
            var client = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let cfd = withUnsafeMutablePointer(to: &client) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &len)
                }
            }
            guard cfd >= 0 else { continue }
            var buf = [UInt8](repeating: 0, count: 16 * 1024)
            let n = read(cfd, &buf, buf.count)
            let raw = n > 0 ? String(bytes: buf[0..<n], encoding: .utf8) ?? "" : ""
            let reply = DispatchQueue.main.sync { MainActor.assumeIsolated { process(raw) } }
            let payload = "HTTP/1.1 \(reply.status) \(reply.reason)\r\nContent-Type: \(reply.type)\r\nContent-Length: \(reply.body.utf8.count)\r\nConnection: close\r\n\r\n\(reply.body)"
            payload.withCString { cstr in
                _ = write(cfd, cstr, strlen(cstr))
            }
            close(cfd)
        }
    }

    @MainActor
    private static func process(_ raw: String) -> (status: Int, reason: String, type: String, body: String) {
        let first = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let pathQ = parts.dropFirst().first.map(String.init) ?? "/"
        let url = URL(string: "http://127.0.0.1\(pathQ)")
        let path = url?.path ?? "/"
        let q = URLComponents(string: pathQ)?.queryItems ?? []
        func item(_ name: String) -> String? {
            q.first(where: { $0.name == name })?.value
        }

        do {
            switch (method, path) {
            case (_, "/health"):
                let screen = HarnessTarget.model.map { String(describing: $0.screen) } ?? "nil"
                return json(200, [
                    "ok": true,
                    "bridge": "microduck-tap",
                    "port": Int(port),
                    "hasModel": HarnessTarget.model != nil,
                    "screen": screen,
                ])
            case (_, "/elements"):
                return json(200, ["elements": dumpElements()])
            case (_, "/tap"):
                if let id = item("id"), !id.isEmpty {
                    guard tap(id: id) else { throw BridgeError("no element \(id)") }
                    return json(200, ["ok": true, "id": id])
                }
                guard let xs = item("x"), let ys = item("y"), let x = Double(xs), let y = Double(ys) else {
                    throw BridgeError("tap needs id= or x=&y=")
                }
                let point = devicePoint(x: x, y: y)
                guard tap(at: point) else { throw BridgeError("nothing at \(point)") }
                return json(200, ["ok": true, "x": x, "y": y, "point": ["x": point.x, "y": point.y]])
            case (_, "/type"):
                let text = item("text") ?? ""
                guard typeText(text) else { throw BridgeError("no text field focused or pin-input") }
                return json(200, ["ok": true, "text": text])
            default:
                return json(404, ["error": "unknown \(path)"])
            }
        } catch {
            return json(400, ["error": error.localizedDescription])
        }
    }

    private static func json(_ status: Int, _ obj: [String: Any]) -> (Int, String, String, String) {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])) ?? Data()
        let body = String(data: data, encoding: .utf8) ?? "{}"
        let reason = status == 200 ? "OK" : "Error"
        return (status, reason, "application/json", body)
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// Harness uses a 430×932 design space. Map onto the key window.
    private static func devicePoint(x: Double, y: Double) -> CGPoint {
        let bounds = keyWindow()?.bounds ?? CGRect(x: 0, y: 0, width: 430, height: 932)
        return CGPoint(x: x / 430 * bounds.width, y: y / 932 * bounds.height)
    }

    @MainActor
    @discardableResult
    private static func tap(id: String) -> Bool {
        if let model = HarnessTarget.model, model.performHarnessAction(id) {
            return true
        }
        guard let window = keyWindow() else { return false }
        if let view = findView(identifier: id, in: window) {
            return activate(view)
        }
        if let ax = findAX(identifier: id, in: window) {
            return ax.accessibilityActivate()
        }
        return false
    }

    @discardableResult
    private static func tap(at point: CGPoint) -> Bool {
        guard let window = keyWindow(), let hit = window.hitTest(point, with: nil) else { return false }
        return activate(hit)
    }

    private static func activate(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if let field = node as? UITextField {
                field.becomeFirstResponder()
                return true
            }
            if let control = node as? UIControl {
                control.sendActions(for: .touchUpInside)
                return true
            }
            if node.accessibilityActivate() { return true }
            current = node.superview
        }
        return view.accessibilityActivate()
    }

    @MainActor
    @discardableResult
    private static func typeText(_ text: String) -> Bool {
        if let field = firstResponder() as? UITextField {
            field.insertText(text)
            field.sendActions(for: .editingChanged)
            return true
        }
        if let model = HarnessTarget.model {
            if model.wifiDraftSSID != nil {
                model.wifiDraftPSK += text
            } else {
                model.pin += text
            }
            return true
        }
        return false
    }

    private static func firstResponder() -> UIView? {
        guard let window = keyWindow() else { return nil }
        return findFirstResponder(in: window)
    }

    private static func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let found = findFirstResponder(in: child) { return found }
        }
        return nil
    }

    private static func findView(identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews {
            if let found = findView(identifier: identifier, in: child) { return found }
        }
        return nil
    }

    private static func deepestTextField(_ view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for child in view.subviews.reversed() {
            if let field = deepestTextField(child) { return field }
        }
        return nil
    }

    private static func findAX(identifier: String, in view: UIView) -> NSObject? {
        for node in axNodes(in: view) {
            let id = (node as? UIView)?.accessibilityIdentifier
                ?? (node.value(forKey: "accessibilityIdentifier") as? String)
            let label = node.accessibilityLabel
            if id == identifier || label == identifier { return node }
        }
        return nil
    }

    private static func axNodes(in view: UIView) -> [NSObject] {
        var out: [NSObject] = [view]
        if let els = view.accessibilityElements as? [NSObject] {
            out.append(contentsOf: els)
        }
        for child in view.subviews {
            out.append(contentsOf: axNodes(in: child))
        }
        return out
    }

    private static func dumpElements() -> [[String: Any]] {
        guard let window = keyWindow() else { return [["error": "no key window"]] }
        var out: [[String: Any]] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ node: NSObject, frame: CGRect) {
            let oid = ObjectIdentifier(node)
            guard !seen.contains(oid) else { return }
            seen.insert(oid)
            let id = (node as? UIView)?.accessibilityIdentifier
                ?? (node.value(forKey: "accessibilityIdentifier") as? String)
                ?? ""
            let label = node.accessibilityLabel ?? ""
            if id.isEmpty && label.isEmpty { return }
            out.append([
                "id": id,
                "label": label,
                "x": frame.midX,
                "y": frame.midY,
                "w": frame.width,
                "h": frame.height,
            ])
        }
        func walk(_ view: UIView) {
            add(view, frame: view.convert(view.bounds, to: window))
            if let els = view.accessibilityElements as? [NSObject] {
                for el in els {
                    let frame = el.accessibilityFrame
                    add(el, frame: frame)
                }
            }
            view.subviews.forEach(walk)
        }
        walk(window)
        return out
    }
}

private struct BridgeError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
