import Foundation
import Testing
@testable import QuotaBarCore

@Test func summaryGroupsEventsByModelInsideDateRange() throws {
    let calendar = Calendar(identifier: .gregorian)
    let start = try #require(DateComponents(calendar: calendar, year: 2026, month: 5, day: 10).date)
    let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
    let events = [
        UsageEvent(
            timestamp: start.addingTimeInterval(60),
            provider: .deepSeek,
            model: "deepseek-chat",
            usage: TokenUsage(inputTokens: 1_000, outputTokens: 500),
            costUSD: Decimal(string: "0.00082")!,
            statusCode: 200,
            durationMS: 420,
            clientLabel: "codex",
            isAnomalous: false
        ),
        UsageEvent(
            timestamp: start.addingTimeInterval(120),
            provider: .deepSeek,
            model: "deepseek-reasoner",
            usage: TokenUsage(inputTokens: 2_000, outputTokens: 1_000),
            costUSD: Decimal(string: "0.00274")!,
            statusCode: 200,
            durationMS: 900,
            clientLabel: "editor",
            isAnomalous: false
        ),
        UsageEvent(
            timestamp: end.addingTimeInterval(60),
            provider: .deepSeek,
            model: "deepseek-chat",
            usage: TokenUsage(inputTokens: 10_000, outputTokens: 10_000),
            costUSD: Decimal(string: "0.0137")!,
            statusCode: 200,
            durationMS: 300,
            clientLabel: nil,
            isAnomalous: false
        )
    ]

    let summary = UsageAggregator.summary(
        for: events,
        interval: DateInterval(start: start, end: end)
    )

    #expect(summary.totalTokens == 4_500)
    #expect(summary.totalCostUSD == Decimal(string: "0.00356")!)
    #expect(summary.byModel.map(\.model) == ["deepseek-v4-flash"])
    #expect(summary.byModel.first?.totalTokens == 4_500)
}

@Test func summaryCanonicalizesV4ModelsAndNormalizesNegativeStoredCosts() throws {
    let calendar = Calendar(identifier: .gregorian)
    let start = try #require(DateComponents(calendar: calendar, year: 2026, month: 5, day: 10).date)
    let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
    let events = [
        UsageEvent(
            timestamp: start.addingTimeInterval(60),
            provider: .deepSeek,
            model: "deepseek-v4-pro[1m]",
            usage: TokenUsage(inputTokens: 100, outputTokens: 20, cacheHitInputTokens: 50),
            costUSD: Decimal(string: "-7.50")!,
            statusCode: 200,
            durationMS: 420,
            clientLabel: "cc-switch",
            isAnomalous: false
        )
    ]

    let summary = UsageAggregator.summary(
        for: events,
        interval: DateInterval(start: start, end: end)
    )
    let trend = UsageAggregator.dailyTrend(
        for: events,
        interval: DateInterval(start: start, end: end),
        calendar: calendar
    )

    #expect(summary.totalCostUSD == Decimal(string: "7.50")!)
    #expect(summary.byModel.map(\.model) == ["deepseek-v4-pro"])
    #expect(trend.first?.totalCostUSD == Decimal(string: "7.50")!)
}

@Test func dailyTrendProducesZeroFilledDays() throws {
    let calendar = Calendar(identifier: .gregorian)
    let start = try #require(DateComponents(calendar: calendar, year: 2026, month: 5, day: 1).date)
    let dayThree = try #require(calendar.date(byAdding: .day, value: 2, to: start))
    let end = try #require(calendar.date(byAdding: .day, value: 4, to: start))
    let events = [
        UsageEvent(
            timestamp: dayThree.addingTimeInterval(30),
            provider: .deepSeek,
            model: "deepseek-chat",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            costUSD: Decimal(string: "0.000082")!,
            statusCode: 200,
            durationMS: 250,
            clientLabel: nil,
            isAnomalous: false
        )
    ]

    let trend = UsageAggregator.dailyTrend(
        for: events,
        interval: DateInterval(start: start, end: end),
        calendar: calendar
    )

    #expect(trend.map(\.totalTokens) == [0, 0, 150, 0])
    #expect(trend[2].totalCostUSD == Decimal(string: "0.000082")!)
}
