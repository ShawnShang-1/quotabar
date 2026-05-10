import Foundation
import Testing
@testable import QuotaBarCore

@Test func v4FlashPricingComputesCostFromCacheHitMissAndOutputTokens() throws {
    let pricing = try DeepSeekPricing.pricing(for: "deepseek-v4-flash")

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "0.448"))
}

@Test func discountedV4ProPricingComputesCostFromCacheHitMissAndOutputTokens() throws {
    let pricing = try DeepSeekPricing.pricing(for: "deepseek-v4-pro")

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "5.365"))
}

@Test func legacyDeepSeekModelNamesUseV4FlashPricing() throws {
    let chat = try DeepSeekPricing.pricing(for: "deepseek-chat")
    let reasoner = try DeepSeekPricing.pricing(for: "deepseek-reasoner")
    let flash = try DeepSeekPricing.pricing(for: "deepseek-v4-flash")

    #expect(chat == flash)
    #expect(reasoner == flash)
}

@Test func unknownModelThrowsPricingError() {
    #expect(throws: DeepSeekPricingError.unsupportedModel("not-a-model")) {
        try DeepSeekPricing.pricing(for: "not-a-model")
    }
}
