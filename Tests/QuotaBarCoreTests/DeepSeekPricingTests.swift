import Foundation
import Testing
@testable import QuotaBarCore

@Test func deepSeekChatAliasUsesV4FlashCostWithCacheSplit() throws {
    let usage = TokenUsage(
        inputTokens: 3_000,
        outputTokens: 3_000,
        cacheHitInputTokens: 1_000,
        cacheMissInputTokens: 2_000
    )

    let cost = try DeepSeekPricing.current.estimateCostUSD(
        model: "deepseek-chat",
        usage: usage
    )

    #expect(cost == Decimal(string: "0.001148")!)
}

@Test func deepSeekReasonerAliasUsesV4FlashRates() throws {
    let usage = TokenUsage(
        inputTokens: 10_000,
        outputTokens: 5_000,
        cacheHitInputTokens: 4_000,
        cacheMissInputTokens: 6_000
    )

    let cost = try DeepSeekPricing.current.estimateCostUSD(
        model: "deepseek-reasoner",
        usage: usage
    )

    #expect(cost == Decimal(string: "0.002352")!)
}

@Test func unknownModelThrowsInsteadOfGuessingPricing() throws {
    let usage = TokenUsage(inputTokens: 1_000, outputTokens: 1_000)

    #expect(throws: DeepSeekPricingError.unsupportedModel("future-deepseek-model")) {
        try DeepSeekPricing.current.estimateCostUSD(
            model: "future-deepseek-model",
            usage: usage
        )
    }
}
