import AppKit

if CommandLine.arguments.contains("--probe") {
    do {
        let snapshot = try CodexQuotaClient().fetch()
        let reset = snapshot.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        print("remaining=\(Int(snapshot.remainingPercent.rounded())) used=\(Int(snapshot.usedPercent.rounded())) reset=\(reset)")
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
