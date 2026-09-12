import Foundation

enum DuckRpcError: LocalizedError {
    case notConnected
    case connectFailed(String)
    case remote(String)
    case timeout(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "还没连上鸭子"
        case .connectFailed(let url):
            return "无法连接 \(url)。先运行 scripts/duck-app-sim up"
        case .remote(let message):
            return message
        case .timeout(let method):
            return "\(method) 超时"
        case .closed:
            return "连接已断开"
        }
    }
}

struct AuthResult: Decodable {
    var authenticated: Bool
    var attempts_remaining: Int?
}

/// Same NDJSON JSON-RPC the web face and `btd` speak. Transport is WebSocket on App-sim.
final class DuckRpc: @unchecked Sendable {
    static let apiVersion = 16
    static let transport = ProcessInfo.processInfo.environment["MICRODUCK_TRANSPORT"] ?? "sim"
    static let simURL = URL(string: ProcessInfo.processInfo.environment["MICRODUCK_SIM_URL"] ?? "ws://127.0.0.1:17432")!
    static let lanURL = URL(string: ProcessInfo.processInfo.environment["MICRODUCK_LAN_URL"] ?? "ws://127.0.0.1:17434")!
    static let cameraStill = ProcessInfo.processInfo.environment["MICRODUCK_CAMERA_STILL"] ?? "http://127.0.0.1:17435/camera.jpg"

    private let url: URL
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var nextId = 1
    private var pending: [Int: (Result<Any, Error>) -> Void] = [:]
    private var buffer = ""
    private var session: URLSession

    init(url: URL = DuckRpc.simURL) {
        self.url = url
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func connect() async throws {
        if task?.state == .running { return }
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receiveLoop()
        try await Task.sleep(nanoseconds: 150_000_000)
        if socket.state != .running {
            throw DuckRpcError.connectFailed(url.absoluteString)
        }
    }

    func close() {
        lock.lock()
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        waiting.values.forEach { $0(.failure(DuckRpcError.closed)) }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        buffer = ""
    }

    func hello() async throws -> Any {
        try await call("hello", params: ["api_version": Self.apiVersion])
    }

    func authenticate(pin: String) async throws -> AuthResult {
        let raw = try await call("system.authenticate", params: ["pin": pin])
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(AuthResult.self, from: data)
    }

    func notify(_ method: String, params: [String: Any] = [:]) {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        task?.send(.string(line)) { _ in }
    }

    @discardableResult
    func call(_ method: String, params: [String: Any] = [:]) async throws -> Any {
        try await connect()
        let id: Int = lock.withLock {
            defer { nextId += 1 }
            return nextId
        }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard var line = String(data: data, encoding: .utf8) else {
            throw DuckRpcError.remote("无法编码 \(method)")
        }
        line += "\n"
        return try await withCheckedThrowingContinuation { continuation in
            var settled = false
            lock.lock()
            pending[id] = { result in
                guard !settled else { return }
                settled = true
                continuation.resume(with: result)
            }
            lock.unlock()
            task?.send(.string(line)) { [weak self] error in
                if let error {
                    self?.finish(id: id, .failure(error))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.finish(id: id, .failure(DuckRpcError.timeout(method)))
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.close()
            case .success(let message):
                let text: String
                switch message {
                case .string(let s):
                    text = s
                case .data(let data):
                    text = String(data: data, encoding: .utf8) ?? ""
                @unknown default:
                    text = ""
                }
                self.ingest(text)
                if self.task?.state == .running {
                    self.receiveLoop()
                }
            }
        }
    }

    private func ingest(_ text: String) {
        buffer += text
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<range.upperBound)
            handleLine(line)
        }
        if !buffer.isEmpty, !buffer.contains("\n"), let data = buffer.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["id"] != nil
        {
            buffer = ""
            handleObject(obj)
        }
    }

    private func handleLine(_ line: String) {
        guard !line.isEmpty, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        handleObject(obj)
    }

    private func jsonId(_ obj: [String: Any]) -> Int? {
        if let i = obj["id"] as? Int { return i }
        if let n = obj["id"] as? NSNumber { return n.intValue }
        return nil
    }

    private func handleObject(_ obj: [String: Any]) {
        guard let id = jsonId(obj) else { return }
        if let error = obj["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "RPC error"
            finish(id: id, .failure(DuckRpcError.remote(message)))
        } else {
            finish(id: id, .success(obj["result"] ?? NSNull()))
        }
    }

    private func finish(id: Int, _ result: Result<Any, Error>) {
        lock.lock()
        let cb = pending.removeValue(forKey: id)
        lock.unlock()
        cb?(result)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
