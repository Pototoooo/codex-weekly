import Foundation
import Testing
@testable import CodexWeekly

@Test func parsesFiveHourAndWeeklyWindows() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":67,"windowDurationMins":300,"resetsAt":1787728125},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1788314925}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":67,"windowDurationMins":300,"resetsAt":1787728125},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1788314925}}}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.fiveHour?.usedPercent == 67)
    #expect(snapshot.fiveHour?.remainingPercent == 33)
    #expect(snapshot.fiveHour?.isFiveHour == true)
    #expect(snapshot.weekly?.usedPercent == 10)
    #expect(snapshot.weekly?.remainingPercent == 90)
    #expect(snapshot.weekly?.isWeekly == true)
}

@Test func parsesLegacyWindows() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300},"secondary":{"usedPercent":42,"windowDurationMins":10080}}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.fiveHour?.remainingPercent == 20)
    #expect(snapshot.weekly?.remainingPercent == 58)
}

@Test func ignoresUnrelatedModelBucketWhenCodexBucketExists() throws {
    let json = #"{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":30,"windowDurationMins":10080}},"base_model_inference":{"primary":{"usedPercent":99,"windowDurationMins":10080},"secondary":null}}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.fiveHour?.usedPercent == 20)
    #expect(snapshot.weekly?.usedPercent == 30)
}

@Test func supportsSingleFiveHourWindow() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":"25","windowDurationMins":"300"},"secondary":null}}}"#
    let snapshot = try #require(try QuotaParser.parseResponseLine(Data(json.utf8)))
    #expect(snapshot.fiveHour?.remainingPercent == 75)
    #expect(snapshot.weekly == nil)
}

@Test func ignoresNotifications() throws {
    let json = #"{"method":"remoteControl/status/changed","params":{}}"#
    #expect(try QuotaParser.parseResponseLine(Data(json.utf8)) == nil)
}
