import Foundation
import Testing
@testable import CodexWeekly

private func parseSub2(_ json: String) throws -> Sub2Snapshot { try Sub2Parser.parse(Data(json.utf8)) }

@Test func sub2SubscriptionKeepsDailyAndWeeklySeparate() throws {
    let snapshot = try parseSub2(#"{"remaining":15,"subscription":{"daily_usage_usd":5,"daily_limit_usd":20,"weekly_usage_usd":30,"weekly_limit_usd":100,"weekly_window_start":"2026-09-10T00:00:00Z","expires_at":"2026-10-01T00:00:00Z"}}"#)
    #expect(snapshot.daily?.remaining == 15)
    #expect(snapshot.weekly?.remaining == 70)
    #expect(snapshot.weekly?.remainingPercent == 70)
    #expect(snapshot.weekly?.reset == nil)
    #expect(snapshot.daily?.reset == nil)
}

@Test func sub2KeyRateLimitsAndReset() throws {
    let snapshot = try parseSub2(#"{"rate_limits":[{"window":"5h","used":1,"limit":2},{"window":"1d","used":4,"limit":10},{"window":"7d","used":"25","limit":"100","reset_at":"2026-09-20T08:00:00.000Z"}]}"#)
    #expect(snapshot.daily?.remaining == 6)
    #expect(snapshot.weekly?.remaining == 75)
    #expect(snapshot.weekly?.reset == ISO8601DateFormatter().date(from: "2026-09-20T08:00:00Z"))
}

@Test func sub2SummaryIsNotWeekly() throws {
    let snapshot = try parseSub2(#"{"remaining":8.5}"#)
    #expect(snapshot.weekly == nil)
    #expect(snapshot.daily == nil)
    #expect(snapshot.summary == 8.5)
}

@Test func sub2ExhaustionClampsAndWrapperWorks() throws {
    let snapshot = try parseSub2(#"{"data":{"subscription":{"daily_usage_usd":30,"daily_limit_usd":20,"weekly_usage_usd":101,"weekly_limit_usd":100}}}"#)
    #expect(snapshot.daily?.remaining == 0)
    #expect(snapshot.weekly?.remainingPercent == 0)
}

@Test func sub2MissingMalformedUnlimitedAreNotFakeZero() {
    for json in [#"{}"#, #"{"subscription":{"daily_limit_usd":20}}"#,
                 #"{"remaining":-1}"#, #"{"remaining":true}"#,
                 #"{"subscription":{"daily_usage_usd":0,"daily_limit_usd":0}}"#,
                 #"{"rate_limits":[{"window":"7d","used":0,"limit":"inf"}]}"#, "<html>login</html>"] {
        #expect(throws: (any Error).self) { try parseSub2(json) }
    }
}

@Test func sub2NormalizesBaseURLs() throws {
    for base in ["https://example.test", "https://example.test/", "https://example.test/v1", "https://example.test/v1/", "https://example.test/v1/usage"] {
        #expect(try Sub2Configuration(baseURL: base, key: "fixture").endpoint.absoluteString == "https://example.test/v1/usage")
    }
    #expect(try Sub2Configuration(baseURL: "https://example.test/proxy/v1", key: "fixture").endpoint.path == "/proxy/v1/usage")
}

@Test func sub2RejectsUnsafeConfiguration() {
    for base in ["http://example.test", "https://user:pass@example.test", "https://example.test?key=x", "https://example.test/#fragment", "not a URL"] {
        #expect(throws: Sub2Error.self) { try Sub2Configuration(baseURL: base, key: "fixture") }
    }
    for key in ["", "  ", "bad\nheader"] {
        #expect(throws: Sub2Error.self) { try Sub2Configuration(baseURL: "https://example.test", key: key) }
    }
}

@Test func sub2ErrorsDoNotEchoSecretsOrServerBody() {
    #expect(Sub2Error.http(401).localizedDescription.contains("401"))
    #expect(Sub2Error.http(429).localizedDescription.contains("429"))
}

@Test func sub2MenuBarAlwaysShowsDailyNotWeekly() throws {
    let both = try parseSub2(#"{"subscription":{"daily_usage_usd":50,"daily_limit_usd":200,"weekly_usage_usd":50,"weekly_limit_usd":500}}"#)
    #expect(both.menuBarTitle == " S2 日 75%")
    let weeklyOnly = try parseSub2(#"{"subscription":{"weekly_usage_usd":50,"weekly_limit_usd":500}}"#)
    #expect(weeklyOnly.menuBarTitle == " S2 日 --%")
    let summaryOnly = try parseSub2(#"{"remaining":100}"#)
    #expect(summaryOnly.menuBarTitle == " S2 日 --%")
}

@Test func quotaSourceSwitchIsBidirectional() {
    let local = QuotaSource(sub2Enabled: false)
    #expect(local.switchTitle == "切换到 Sub2 额度")
    #expect(local.other == .sub2)
    #expect(local.other.switchTitle == "切换到 Codex 本地额度")
    #expect(local.other.other == local)
    #expect(QuotaSource(sub2Enabled: true).other == .local)
}
