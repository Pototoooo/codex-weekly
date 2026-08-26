import Foundation

struct QuotaWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var isFiveHour: Bool {
        // The rolling five-hour Codex window is represented as 300 minutes.
        abs(windowDurationMinutes - 300) <= 15
    }

    var isWeekly: Bool {
        // The Codex API currently represents a week as 10,080 minutes. Allow a
        // little tolerance so a server-side rounding change does not break UI.
        abs(windowDurationMinutes - 10_080) <= 60
    }
}

struct QuotaSnapshot: Equatable, Sendable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?

    var preferredDisplayWindow: QuotaWindow? {
        fiveHour ?? weekly
    }
}

enum QuotaParsingError: LocalizedError {
    case missingResult
    case missingRateLimits
    case missingWindow

    var errorDescription: String? {
        switch self {
        case .missingResult: "Codex 未返回额度结果"
        case .missingRateLimits: "Codex 返回结果中没有额度数据"
        case .missingWindow: "没有找到 5 小时或周额度窗口"
        }
    }
}

enum QuotaParser {
    static func parseResponseLine(_ data: Data) throws -> QuotaSnapshot? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }

        // Ignore notifications and the initialize response.
        guard let id = root["id"] as? NSNumber, id.intValue == 2 else { return nil }
        guard let result = root["result"] as? [String: Any] else {
            throw QuotaParsingError.missingResult
        }

        var candidates: [[String: Any]] = []
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = buckets["codex"] as? [String: Any] {
                candidates.append(codex)
            }
        }
        if let legacy = result["rateLimits"] as? [String: Any] {
            candidates.append(legacy)
        }
        // Older app-server builds may not expose a bucket named "codex". Only
        // then consider other buckets so an unrelated model limit cannot
        // override the actual Codex windows returned by the legacy field.
        if candidates.isEmpty,
           let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            candidates.append(contentsOf: buckets.values.compactMap { $0 as? [String: Any] })
        }
        guard !candidates.isEmpty else { throw QuotaParsingError.missingRateLimits }

        let windows = candidates.flatMap { bucket -> [[String: Any]] in
            [bucket["primary"], bucket["secondary"]].compactMap { $0 as? [String: Any] }
        }

        let parsedWindows = windows.compactMap(parseWindow)
        let fiveHour = parsedWindows.first(where: \.isFiveHour)
        let weekly = parsedWindows.first(where: \.isWeekly)

        guard fiveHour != nil || weekly != nil else {
            throw QuotaParsingError.missingWindow
        }
        return QuotaSnapshot(fiveHour: fiveHour, weekly: weekly)
    }

    private static func parseWindow(_ object: [String: Any]) -> QuotaWindow? {
        guard let used = number(object["usedPercent"]),
              let duration = number(object["windowDurationMins"]) else {
            return nil
        }
        let reset = number(object["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return QuotaWindow(
            usedPercent: used,
            windowDurationMinutes: Int(duration),
            resetsAt: reset
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
