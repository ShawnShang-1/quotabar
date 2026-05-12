import Foundation
import Testing
@testable import QuotaBarCore

@Test func aggregationSumsUsageAndCostAcrossRecords() throws {
    let records = [
        UsageRecord(
            model: "deepseek-v4-flash",
            promptCacheHitTokens: 500_000,
            promptCacheMissTokens: 100_000,
            completionTokens: 25_000
        ),
        UsageRecord(
            model: "deepseek-chat",
            promptCacheHitTokens: 500_000,
            promptCacheMissTokens: 0,
            completionTokens: 75_000
        )
    ]

    let summary = try UsageAggregator.aggregate(records)

    #expect(summary.promptCacheHitTokens == 1_000_000)
    #expect(summary.promptCacheMissTokens == 100_000)
    #expect(summary.completionTokens == 100_000)
    #expect(summary.totalTokens == 1_200_000)
    #expect(summary.totalCostUSD == Decimal(string: "0.32"))
}

@Test func aggregationGroupsUsageByCanonicalModel() throws {
    let records = [
        UsageRecord(
            model: "deepseek-v4-flash",
            promptCacheHitTokens: 10,
            promptCacheMissTokens: 20,
            completionTokens: 30
        ),
        UsageRecord(
            model: "deepseek-reasoner",
            promptCacheHitTokens: 40,
            promptCacheMissTokens: 50,
            completionTokens: 60
        ),
        UsageRecord(
            model: "deepseek-v4-pro",
            promptCacheHitTokens: 70,
            promptCacheMissTokens: 80,
            completionTokens: 90
        )
    ]

    let summary = try UsageAggregator.aggregate(records)

    #expect(summary.byModel["deepseek-v4-flash"]?.totalTokens == 210)
    #expect(summary.byModel["deepseek-v4-pro"]?.totalTokens == 240)
}

@Test func aggregationPropagatesUnsupportedModelErrors() {
    let records = [
        UsageRecord(
            model: "unknown",
            promptCacheHitTokens: 1,
            promptCacheMissTokens: 2,
            completionTokens: 3
        )
    ]

    #expect(throws: DeepSeekPricingError.unsupportedModel("unknown")) {
        try UsageAggregator.aggregate(records)
    }
}
