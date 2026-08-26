import AppKit

if CommandLine.arguments.contains("--probe") {
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
