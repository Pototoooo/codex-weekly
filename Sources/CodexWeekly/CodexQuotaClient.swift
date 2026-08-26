import Foundation

enum CodexQuotaError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case timedOut
    case serverError(String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "找不到 Codex CLI，请先安装或登录 Codex"
        case .launchFailed(let message):
            "无法启动 Codex：\(message)"
        case .timedOut:
            "读取额度超时"
        case .serverError(let message):
            "Codex 返回错误：\(message)"
        case .noResponse:
            "Codex 未返回额度"
        }
    }
}

final class CodexQuotaClient: @unchecked Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func fetch() throws -> QuotaSnapshot {
        guard let executable = Self.findCodexExecutable() else {
            throw CodexQuotaError.executableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let accumulator = ResponseAccumulator()

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            accumulator.append(chunk)
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexQuotaError.launchFailed(error.localizedDescription)
        }

        let requests: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-weekly",
                        "title": "Codex Weekly",
                        "version": AppVersion.current
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["id": 2, "method": "account/rateLimits/read", "params": NSNull()]
        ]

        do {
            for request in requests {
                let data = try JSONSerialization.data(withJSONObject: request)
                input.fileHandleForWriting.write(data)
                input.fileHandleForWriting.write(Data([0x0A]))
            }
        } catch {
            process.terminate()
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexQuotaError.launchFailed(error.localizedDescription)
        }

        let result = accumulator.wait(timeout: timeout)

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        guard let result else { throw CodexQuotaError.timedOut }
        return try result.get()
    }

    static func findCodexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class ResponseAccumulator: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var received: Result<QuotaSnapshot, Error>?

    func append(_ chunk: Data) {
        condition.lock()
        defer { condition.unlock() }
        guard received == nil else { return }

        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            do {
                if let snapshot = try QuotaParser.parseResponseLine(line) {
                    received = .success(snapshot)
                    condition.broadcast()
                    return
                }
                if let root = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = root["id"] as? NSNumber, id.intValue == 2,
                   let error = root["error"] as? [String: Any] {
                    let message = (error["message"] as? String) ?? "未知错误"
                    received = .failure(CodexQuotaError.serverError(message))
                    condition.broadcast()
                    return
                }
            } catch {
                received = .failure(error)
                condition.broadcast()
                return
            }
        }
    }

    func wait(timeout: TimeInterval) -> Result<QuotaSnapshot, Error>? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while received == nil && condition.wait(until: deadline) {}
        return received
    }
}

enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
