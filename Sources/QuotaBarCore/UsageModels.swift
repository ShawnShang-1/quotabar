import Foundation

public enum ProviderKind: String, Codable, Equatable, Sendable {
    case deepSeek = "deepseek"
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheHitInputTokens: Int
    public var cacheMissInputTokens: Int

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheHitInputTokens: Int? = nil,
        cacheMissInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitInputTokens = cacheHitInputTokens ?? 0
        self.cacheMissInputTokens = cacheMissInputTokens ?? inputTokens - self.cacheHitInputTokens
    }

    public init(promptTokens: Int, completionTokens: Int, totalTokens _: Int) {
        self.init(inputTokens: promptTokens, outputTokens: completionTokens)
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }
}

public struct UsageEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var provider: ProviderKind
    public var model: String
    public var usage: TokenUsage
    public var costUSD: Decimal
    public var statusCode: Int
    public var durationMS: Int
    public var clientLabel: String?
    public var isAnomalous: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        provider: ProviderKind,
        model: String,
        usage: TokenUsage,
        costUSD: Decimal,
        statusCode: Int,
        durationMS: Int,
        clientLabel: String?,
        isAnomalous: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.usage = usage
        self.costUSD = costUSD
        self.statusCode = statusCode
        self.durationMS = durationMS
        self.clientLabel = clientLabel
        self.isAnomalous = isAnomalous
    }
}

public struct UsageRecord: Equatable, Sendable {
    public var model: String
    public var promptCacheHitTokens: Int
    public var promptCacheMissTokens: Int
    public var completionTokens: Int

    public init(
        model: String,
        promptCacheHitTokens: Int,
        promptCacheMissTokens: Int,
        completionTokens: Int
    ) {
        self.model = model
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
        self.completionTokens = completionTokens
    }

    public var totalTokens: Int {
        promptCacheHitTokens + promptCacheMissTokens + completionTokens
    }
}

public struct UsageModelSummary: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public var model: String
    public var promptCacheHitTokens: Int
    public var promptCacheMissTokens: Int
    public var completionTokens: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalCostUSD: Decimal

    public init(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        totalCostUSD: Decimal,
        promptCacheHitTokens: Int = 0,
        promptCacheMissTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalCostUSD = totalCostUSD
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens ?? max(0, inputTokens - promptCacheHitTokens)
        self.completionTokens = completionTokens ?? outputTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }
}

public struct ModelBreakdown: Equatable, RandomAccessCollection, Sendable {
    public typealias Index = Int
    public typealias Element = UsageModelSummary

    private var rows: [UsageModelSummary]

    public init(_ rows: [UsageModelSummary]) {
        self.rows = rows
    }

    public var startIndex: Int { rows.startIndex }
    public var endIndex: Int { rows.endIndex }

    public subscript(position: Int) -> UsageModelSummary {
        rows[position]
    }

    public subscript(model: String) -> UsageModelSummary? {
        rows.first { $0.model == model }
    }
}

public struct UsageSummary: Equatable, Sendable {
    public var promptCacheHitTokens: Int
    public var promptCacheMissTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var totalCostUSD: Decimal
    public var byModel: ModelBreakdown

    public init(
        promptCacheHitTokens: Int = 0,
        promptCacheMissTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int,
        totalCostUSD: Decimal,
        byModel: ModelBreakdown
    ) {
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.byModel = byModel
    }
}

public struct DailyUsagePoint: Equatable, Identifiable, Sendable {
    public var id: Date { day }
    public var day: Date
    public var totalTokens: Int
    public var totalCostUSD: Decimal

    public init(day: Date, totalTokens: Int, totalCostUSD: Decimal) {
        self.day = day
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
    }
}
