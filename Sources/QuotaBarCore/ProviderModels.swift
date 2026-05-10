import Foundation

public enum ProviderCapability: String, Codable, Hashable, Sendable {
    case balance
    case tokenPricing
    case usageLedger
    case quotaWindow
}

public protocol ProviderAdapter: Sendable {
    var provider: ProviderKind { get }
    var capabilities: Set<ProviderCapability> { get }
}

public struct ProviderBalanceSnapshot: Codable, Equatable, Sendable {
    public var provider: ProviderKind
    public var currency: String
    public var totalBalance: Decimal
    public var isAvailable: Bool
    public var updatedAt: Date

    public init(
        provider: ProviderKind,
        currency: String,
        totalBalance: Decimal,
        isAvailable: Bool,
        updatedAt: Date
    ) {
        self.provider = provider
        self.currency = currency
        self.totalBalance = totalBalance
        self.isAvailable = isAvailable
        self.updatedAt = updatedAt
    }
}

public enum UsageAlertKind: String, Codable, Equatable, Sendable {
    case lowBalance
    case dailyBudgetExceeded
    case usageSpike
    case providerUnavailable
}

public struct UsageAlertCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: UsageAlertKind
    public var title: String
    public var body: String

    public init(id: String, kind: UsageAlertKind, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public struct UsageAlertPolicy: Equatable, Sendable {
    public var lowBalanceThreshold: Decimal
    public var dailyBudgetUSD: Decimal
    public var spikeMultiplier: Double

    public init(lowBalanceThreshold: Decimal, dailyBudgetUSD: Decimal, spikeMultiplier: Double) {
        self.lowBalanceThreshold = lowBalanceThreshold
        self.dailyBudgetUSD = dailyBudgetUSD
        self.spikeMultiplier = spikeMultiplier
    }

    public func evaluate(
        balance: ProviderBalanceSnapshot?,
        today: UsageSummary,
        currentHourCostUSD: Decimal,
        hourlyBaselineCostUSD: Decimal
    ) -> [UsageAlertCandidate] {
        var alerts: [UsageAlertCandidate] = []

        if let balance, !balance.isAvailable {
            alerts.append(
                UsageAlertCandidate(
                    id: "deepseek-unavailable",
                    kind: .providerUnavailable,
                    title: "DeepSeek unavailable",
                    body: "DeepSeek reports this account is not currently available."
                )
            )
        }

        if let balance, balance.totalBalance <= lowBalanceThreshold {
            alerts.append(
                UsageAlertCandidate(
                    id: "deepseek-low-balance",
                    kind: .lowBalance,
                    title: "DeepSeek balance is low",
                    body: "\(balance.currency) \(balance.totalBalance) remaining."
                )
            )
        }

        if dailyBudgetUSD > 0, today.totalCostUSD >= dailyBudgetUSD {
            alerts.append(
                UsageAlertCandidate(
                    id: "deepseek-daily-budget",
                    kind: .dailyBudgetExceeded,
                    title: "Daily AI spend over budget",
                    body: "Today is at $\(today.totalCostUSD), above the $\(dailyBudgetUSD) budget."
                )
            )
        }

        let baseline = NSDecimalNumber(decimal: hourlyBaselineCostUSD).doubleValue
        let current = NSDecimalNumber(decimal: currentHourCostUSD).doubleValue
        if baseline > 0, current >= baseline * spikeMultiplier {
            alerts.append(
                UsageAlertCandidate(
                    id: "deepseek-hourly-spike",
                    kind: .usageSpike,
                    title: "AI usage spike detected",
                    body: "The current hour is \(String(format: "%.1f", current / baseline))x the recent hourly baseline."
                )
            )
        }

        return alerts
    }
}
