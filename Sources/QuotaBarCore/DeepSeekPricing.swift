import Foundation

public enum DeepSeekPricingError: Error, Equatable, Sendable {
    case unsupportedModel(String)
}

public struct DeepSeekModelPricing: Equatable, Sendable {
    public var canonicalModel: String
    public var cacheHitInputUSDPerMillion: Decimal
    public var cacheMissInputUSDPerMillion: Decimal
    public var outputUSDPerMillion: Decimal

    public init(
        canonicalModel: String,
        cacheHitInputUSDPerMillion: Decimal,
        cacheMissInputUSDPerMillion: Decimal,
        outputUSDPerMillion: Decimal
    ) {
        self.canonicalModel = canonicalModel
        self.cacheHitInputUSDPerMillion = cacheHitInputUSDPerMillion
        self.cacheMissInputUSDPerMillion = cacheMissInputUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
    }

    public func costUSD(
        promptCacheHitTokens: Int,
        promptCacheMissTokens: Int,
        completionTokens: Int
    ) -> Decimal {
        (
            Decimal(promptCacheHitTokens) * cacheHitInputUSDPerMillion
                + Decimal(promptCacheMissTokens) * cacheMissInputUSDPerMillion
                + Decimal(completionTokens) * outputUSDPerMillion
        ) / Decimal(1_000_000)
    }
}

public struct DeepSeekPricing: Sendable {
    public static let current = DeepSeekPricing()

    private static let v4Flash = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-flash",
        cacheHitInputUSDPerMillion: Decimal(string: "0.0028")!,
        cacheMissInputUSDPerMillion: Decimal(string: "0.14")!,
        outputUSDPerMillion: Decimal(string: "0.28")!
    )

    private static let v4Pro = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-pro",
        cacheHitInputUSDPerMillion: Decimal(string: "0.0145")!,
        cacheMissInputUSDPerMillion: Decimal(string: "1.74")!,
        outputUSDPerMillion: Decimal(string: "3.48")!
    )

    private static let v4ProDiscounted = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-pro",
        cacheHitInputUSDPerMillion: Decimal(string: "0.003625")!,
        cacheMissInputUSDPerMillion: Decimal(string: "0.435")!,
        outputUSDPerMillion: Decimal(string: "0.87")!
    )

    private static let v4ProDiscountEndsAt = Date(timeIntervalSince1970: 1_780_243_200)

    public init() {}

    public static func pricing(for model: String, at date: Date = .now) throws -> DeepSeekModelPricing {
        switch model {
        case "deepseek-chat", "deepseek-reasoner", "deepseek-v4-flash":
            v4Flash
        case "deepseek-v4-pro":
            date < v4ProDiscountEndsAt ? v4ProDiscounted : v4Pro
        default:
            throw DeepSeekPricingError.unsupportedModel(model)
        }
    }

    public func estimateCostUSD(model: String, usage: TokenUsage, at date: Date = .now) throws -> Decimal {
        let pricing = try Self.pricing(for: model, at: date)
        return pricing.costUSD(
            promptCacheHitTokens: usage.cacheHitInputTokens,
            promptCacheMissTokens: usage.cacheMissInputTokens,
            completionTokens: usage.outputTokens
        )
    }

    public static func canonicalModel(for model: String, at date: Date = .now) throws -> String {
        try pricing(for: model, at: date).canonicalModel
    }
}
