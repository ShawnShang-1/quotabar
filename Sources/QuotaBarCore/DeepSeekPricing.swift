import Foundation

public enum DeepSeekPricingError: Error, Equatable, Sendable {
    case unsupportedModel(String)
}

public struct DeepSeekModelPricing: Codable, Equatable, Sendable {
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

    public static let defaultV4FlashCNY = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-flash",
        cacheHitInputUSDPerMillion: Decimal(string: "0.02")!,
        cacheMissInputUSDPerMillion: Decimal(string: "1")!,
        outputUSDPerMillion: Decimal(string: "2")!
    )

    public static let defaultV4ProCNY = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-pro",
        cacheHitInputUSDPerMillion: Decimal(string: "0.025")!,
        cacheMissInputUSDPerMillion: Decimal(string: "3")!,
        outputUSDPerMillion: Decimal(string: "6")!
    )

    public static let standardV4ProCNY = DeepSeekModelPricing(
        canonicalModel: "deepseek-v4-pro",
        cacheHitInputUSDPerMillion: Decimal(string: "0.1")!,
        cacheMissInputUSDPerMillion: Decimal(string: "12")!,
        outputUSDPerMillion: Decimal(string: "24")!
    )
}

public struct DeepSeekPricingCatalog: Codable, Equatable, Sendable {
    public var v4Flash: DeepSeekModelPricing
    public var v4Pro: DeepSeekModelPricing

    public init(v4Flash: DeepSeekModelPricing, v4Pro: DeepSeekModelPricing) {
        self.v4Flash = v4Flash
        self.v4Pro = v4Pro
    }

    public static let defaultCNY = DeepSeekPricingCatalog(
        v4Flash: .defaultV4FlashCNY,
        v4Pro: .defaultV4ProCNY
    )

    public func pricing(for model: String) throws -> DeepSeekModelPricing {
        switch DeepSeekPricing.baseModelName(for: model) {
        case "deepseek-chat", "deepseek-reasoner", "deepseek-v4-flash":
            v4Flash
        case "deepseek-v4-pro":
            v4Pro
        default:
            throw DeepSeekPricingError.unsupportedModel(model)
        }
    }

    public func estimateCostUSD(model: String, usage: TokenUsage) throws -> Decimal {
        let pricing = try pricing(for: model)
        return pricing.costUSD(
            promptCacheHitTokens: usage.cacheHitInputTokens,
            promptCacheMissTokens: usage.cacheMissInputTokens,
            completionTokens: usage.outputTokens
        )
    }
}

public struct DeepSeekPricing: Sendable {
    public static let current = DeepSeekPricing()

    private static let v4Flash = DeepSeekModelPricing.defaultV4FlashCNY
    private static let v4Pro = DeepSeekModelPricing.standardV4ProCNY
    private static let v4ProDiscounted = DeepSeekModelPricing.defaultV4ProCNY

    private static let v4ProDiscountEndsAt = Date(timeIntervalSince1970: 1_780_243_200)

    public init() {}

    public static func pricing(for model: String, at date: Date = .now) throws -> DeepSeekModelPricing {
        switch baseModelName(for: model) {
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

    public static func baseModelName(for model: String) -> String {
        guard let suffixStart = model.lastIndex(of: "["), model.hasSuffix("]") else {
            return model
        }
        return String(model[..<suffixStart])
    }
}
