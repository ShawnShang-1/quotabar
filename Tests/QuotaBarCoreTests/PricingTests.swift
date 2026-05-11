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

    #expect(cost == Decimal(string: "0.4228"))
}

@Test func discountedV4ProPricingComputesCostFromCacheHitMissAndOutputTokens() throws {
    let pricing = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro",
        at: Date(timeIntervalSince1970: 1_778_688_000)
    )

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "1.308625"))
}

@Test func v4ProPricingUsesStandardRatesAfterTemporaryDiscountExpires() throws {
    let pricing = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro",
        at: Date(timeIntervalSince1970: 1_780_249_600)
    )

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "5.2345"))
}

@Test func legacyDeepSeekModelNamesUseV4FlashPricing() throws {
    let chat = try DeepSeekPricing.pricing(for: "deepseek-chat")
    let reasoner = try DeepSeekPricing.pricing(for: "deepseek-reasoner")
    let flash = try DeepSeekPricing.pricing(for: "deepseek-v4-flash")
    let flashContext = try DeepSeekPricing.pricing(for: "deepseek-v4-flash[1m]")

    #expect(chat == flash)
    #expect(reasoner == flash)
    #expect(flashContext == flash)
}

@Test func contextWindowSuffixDoesNotAffectV4ProPricing() throws {
    let base = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro",
        at: Date(timeIntervalSince1970: 1_778_688_000)
    )
    let oneMillion = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro[1m]",
        at: Date(timeIntervalSince1970: 1_778_688_000)
    )

    #expect(oneMillion == base)
}

@Test func unknownModelThrowsPricingError() {
    #expect(throws: DeepSeekPricingError.unsupportedModel("not-a-model")) {
        try DeepSeekPricing.pricing(for: "not-a-model")
    }
}
