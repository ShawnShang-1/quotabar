import Foundation
import Testing
@testable import QuotaBarCore

@Test func v4FlashPricingComputesCNYCostFromCacheHitMissAndOutputTokens() throws {
    let pricing = try DeepSeekPricing.pricing(for: "deepseek-v4-flash")

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "3.02"))
}

@Test func v4ProPricingUsesManualDefaultCNYRates() throws {
    let pricing = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro",
        at: Date(timeIntervalSince1970: 1_778_688_000)
    )

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "9.025"))
}

@Test func v4ProPricingStaysOnManualDefaultRatesAcrossDates() throws {
    let pricing = try DeepSeekPricing.pricing(
        for: "deepseek-v4-pro",
        at: Date(timeIntervalSince1970: 1_780_249_600)
    )

    let cost = pricing.costUSD(
        promptCacheHitTokens: 1_000_000,
        promptCacheMissTokens: 1_000_000,
        completionTokens: 1_000_000
    )

    #expect(cost == Decimal(string: "9.025"))
}

@Test func customPricingCatalogOverridesV4FlashAndProRates() throws {
    let catalog = DeepSeekPricingCatalog(
        v4Flash: DeepSeekModelPricing(
            canonicalModel: "deepseek-v4-flash",
            cacheHitInputUSDPerMillion: Decimal(string: "0.20")!,
            cacheMissInputUSDPerMillion: Decimal(string: "10")!,
            outputUSDPerMillion: Decimal(string: "20")!
        ),
        v4Pro: DeepSeekModelPricing(
            canonicalModel: "deepseek-v4-pro",
            cacheHitInputUSDPerMillion: Decimal(string: "0.25")!,
            cacheMissInputUSDPerMillion: Decimal(string: "30")!,
            outputUSDPerMillion: Decimal(string: "60")!
        )
    )

    let flashCost = try catalog.estimateCostUSD(
        model: "deepseek-v4-flash[1m]",
        usage: TokenUsage(inputTokens: 2_000_000, outputTokens: 1_000_000, cacheHitInputTokens: 1_000_000)
    )
    let proCost = try catalog.estimateCostUSD(
        model: "deepseek-v4-pro[1m]",
        usage: TokenUsage(inputTokens: 2_000_000, outputTokens: 1_000_000, cacheHitInputTokens: 1_000_000)
    )

    #expect(flashCost == Decimal(string: "30.20"))
    #expect(proCost == Decimal(string: "90.25"))
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
