import Foundation
import CoreFoundation

struct Sub2Window: Equatable, Sendable {
    let used: Double
    let limit: Double
    let reset: Date?
    var remaining: Double { max(0, limit - used) }
    var remainingPercent: Double { min(100, max(0, remaining / limit * 100)) }
}

struct Sub2Snapshot: Equatable, Sendable {
    let daily: Sub2Window?
    let weekly: Sub2Window?
    let summary: Double?
    let scope: String
    let fetchedAt: Date
    var menuBarTitle: String {
        guard let daily else { return " S2 日 --%" }
        return " S2 日 \(Int(daily.remainingPercent.rounded()))%"
    }
}

enum Sub2Error: LocalizedError {
    case configuration, missingKey, invalidData, http(Int), network, keychain
    var errorDescription: String? {
        switch self {
        case .configuration: "请输入有效的 HTTPS Base URL（不含账号、查询参数或片段）"
        case .missingKey: "请先配置 Sub2API Key"
        case .invalidData: "平台未返回可识别的额度；请核对部署版本"
        case .http(let code): "Sub2API HTTP \(code)；请检查 Key、权限或稍后重试"
        case .network: "Sub2API 网络请求失败；请检查网络后重试"
        case .keychain: "无法读取或保存系统钥匙串"
        }
    }
}

enum Sub2Parser {
    static func parse(_ data: Data, now: Date = Date()) throws -> Sub2Snapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Sub2Error.invalidData
        }
        let object = (root["data"] as? [String: Any]) ?? root
        var daily: Sub2Window?
        var weekly: Sub2Window?
        var scope = "Key 配额"
        if let subscription = object["subscription"] as? [String: Any] {
            scope = "订阅配额（同订阅可能由多个 Key 共用）"
            daily = window(subscription, used: "daily_usage_usd", limit: "daily_limit_usd", reset: "daily_reset_at")
            // Do not invent reset timestamps from calendar assumptions or expiry.
            weekly = window(subscription, used: "weekly_usage_usd", limit: "weekly_limit_usd", reset: "weekly_reset_at")
        } else if let limits = object["rate_limits"] as? [[String: Any]] {
            for entry in limits {
                if entry["window"] as? String == "1d" { daily = window(entry) }
                if entry["window"] as? String == "7d" { weekly = window(entry) }
            }
        }
        // A top-level remaining value is NOT a weekly allowance. Negative means unlimited.
        let summary = number(object["remaining"]).flatMap { $0 >= 0 ? $0 : nil }
        guard daily != nil || weekly != nil || summary != nil else { throw Sub2Error.invalidData }
        return Sub2Snapshot(daily: daily, weekly: weekly, summary: summary, scope: scope, fetchedAt: now)
    }

    private static func window(_ object: [String: Any], used: String = "used", limit: String = "limit", reset: String = "reset_at") -> Sub2Window? {
        guard let u = number(object[used]), let l = number(object[limit]), u >= 0, l > 0 else { return nil }
        return Sub2Window(used: u, limit: l, reset: date(object[reset]))
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        let n = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return n.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func date(_ value: Any?) -> Date? {
        if let s = value as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        return number(value).map { Date(timeIntervalSince1970: $0) }
    }
}

struct Sub2Configuration: Sendable {
    let endpoint: URL
    let key: String
    init(baseURL: String, key: String) throws {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw Sub2Error.configuration
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/v1/usage") { path += path.hasSuffix("/v1") ? "/usage" : "/v1/usage" }
        parts.path = path
        guard let url = parts.url else { throw Sub2Error.configuration }
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanKey.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw Sub2Error.missingKey }
        endpoint = url
        self.key = cleanKey
    }
}

// Refuse all redirects so credentials cannot be forwarded to a different endpoint.
final class Sub2QuotaClient: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func fetch(_ config: Sub2Configuration) async throws -> Sub2Snapshot {
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 20
        settings.timeoutIntervalForResource = 25
        settings.httpCookieStorage = nil
        settings.urlCache = nil
        let session = URLSession(configuration: settings, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: config.endpoint)
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw Sub2Error.network }
        guard let http = response as? HTTPURLResponse else { throw Sub2Error.network }
        guard http.statusCode == 200 else { throw Sub2Error.http(http.statusCode) }
        guard data.count <= 2_000_000 else { throw Sub2Error.invalidData }
        do { return try Sub2Parser.parse(data) } catch { throw Sub2Error.invalidData }
    }
}

// The menu action always offers the other source, independent of fetch success.
enum QuotaSource: Equatable {
    case local, sub2
    init(sub2Enabled: Bool) { self = sub2Enabled ? .sub2 : .local }
    var other: QuotaSource { self == .local ? .sub2 : .local }
    var switchTitle: String {
        other == .sub2 ? "切换到 Sub2 额度" : "切换到 Codex 本地额度"
    }
}
