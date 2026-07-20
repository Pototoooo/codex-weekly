import Foundation
import Testing
@testable import CodexWeekly

@Test func parsesWeeklyPrimaryWindow() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1784972170},"secondary":null},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1784972170}}}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.usedPercent == 17)
    #expect(snapshot.remainingPercent == 83)
    #expect(snapshot.isWeekly)
}

@Test func picksWeeklyOverShortWindow() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300},"secondary":{"usedPercent":42,"windowDurationMins":10080}}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.usedPercent == 42)
    #expect(snapshot.remainingPercent == 58)
}

@Test func ignoresNotifications() throws {
    let json = #"{"method":"remoteControl/status/changed","params":{}}"#
    #expect(try QuotaParser.parseResponseLine(Data(json.utf8)) == nil)
}
