import AppKit

if CommandLine.arguments.contains("--sub2-probe") {
    // Secret arrives on stdin, not in argv, preferences, or log output.
    let base = ProcessInfo.processInfo.environment["SUB2_BASE_URL"] ?? "https://dodoki.cc"
    let save = CommandLine.arguments.contains("--save-sub2")
    let secret = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    Task.detached {
        do {
            let endpoint = try Sub2Configuration(baseURL: base, key: "placeholder").endpoint
            let key = secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? try Sub2Keychain.read(endpoint: endpoint) : secret
            let config = try Sub2Configuration(baseURL: base, key: key)
            let snapshot = try await Sub2QuotaClient().fetch(config)
            if save {
                try Sub2Keychain.save(config)
                let defaults = UserDefaults(suiteName: "local.codex.weekly")!
                defaults.set(base, forKey: "sub2BaseURL")
                defaults.set(true, forKey: "sub2Enabled")
            }
            func fields(_ name: String, _ w: Sub2Window?) -> String {
                guard let w else { return "\(name)=unknown" }
                let reset = w.reset.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                return "\(name)Used=\(w.used) \(name)Limit=\(w.limit) \(name)Remaining=\(w.remaining) \(name)Reset=\(reset)"
            }
            print("source=Sub2API " + fields("daily", snapshot.daily) + " " + fields("weekly", snapshot.weekly))
            print("scope=\(snapshot.scope) savedToKeychain=\(save)")
            exit(EXIT_SUCCESS)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--probe") {
    do {
        let snapshot = try CodexQuotaClient().fetch()
        func fields(prefix: String, window: QuotaWindow?) -> [String] {
            guard let window else {
                return ["\(prefix)Remaining=unknown", "\(prefix)Used=unknown", "\(prefix)Reset=unknown"]
            }
            let reset = window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
            return [
                "\(prefix)Remaining=\(Int(window.remainingPercent.rounded()))",
                "\(prefix)Used=\(Int(window.usedPercent.rounded()))",
                "\(prefix)Reset=\(reset)"
            ]
        }
        print((fields(prefix: "fiveHour", window: snapshot.fiveHour)
            + fields(prefix: "weekly", window: snapshot.weekly)).joined(separator: " "))
        exit(EXIT_SUCCESS)
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
