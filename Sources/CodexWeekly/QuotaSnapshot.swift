import Foundation

struct QuotaSnapshot: Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var isWeekly: Bool {
        // The Codex API currently represents a week as 10,080 minutes. Allow a
        // little tolerance so a server-side rounding change does not break UI.
        abs(windowDurationMinutes - 10_080) <= 60
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
        case .missingWindow: "没有找到周额度窗口"
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
            for value in buckets.values {
                if let bucket = value as? [String: Any],
                   !candidates.contains(where: { NSDictionary(dictionary: $0).isEqual(to: bucket) }) {
                    candidates.append(bucket)
                }
            }
        }
        if let legacy = result["rateLimits"] as? [String: Any] {
            candidates.append(legacy)
        }
        guard !candidates.isEmpty else { throw QuotaParsingError.missingRateLimits }

        let windows = candidates.flatMap { bucket -> [[String: Any]] in
            [bucket["primary"], bucket["secondary"]].compactMap { $0 as? [String: Any] }
        }

        // Prefer the explicit seven-day window. If the service ever omits its
        // duration, selecting the longest window remains the least surprising.
        let selected = windows.first(where: {
            guard let minutes = number($0["windowDurationMins"]) else { return false }
            return abs(Int(minutes) - 10_080) <= 60
        }) ?? windows.max(by: {
            (number($0["windowDurationMins"]) ?? 0) < (number($1["windowDurationMins"]) ?? 0)
        })

        guard let selected,
              let used = number(selected["usedPercent"]),
              let duration = number(selected["windowDurationMins"]) else {
            throw QuotaParsingError.missingWindow
        }

        let reset = number(selected["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return QuotaSnapshot(
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
