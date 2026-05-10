import Foundation
import QuotaBarCore
import SwiftData

@Model
final class UsageLedgerEntry {
    var id: UUID
    var timestamp: Date
    var providerRawValue: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheHitInputTokens: Int
    var cacheMissInputTokens: Int
    var costUSDValue: String
    var statusCode: Int
    var durationMS: Int
    var clientLabel: String?
    var isAnomalous: Bool

    init(event: UsageEvent) {
        id = event.id
        timestamp = event.timestamp
        providerRawValue = event.provider.rawValue
        model = event.model
        inputTokens = event.usage.inputTokens
        outputTokens = event.usage.outputTokens
        cacheHitInputTokens = event.usage.cacheHitInputTokens
        cacheMissInputTokens = event.usage.cacheMissInputTokens
        costUSDValue = event.costUSD.description
        statusCode = event.statusCode
        durationMS = event.durationMS
        clientLabel = event.clientLabel
        isAnomalous = event.isAnomalous
    }

    var usageEvent: UsageEvent? {
        guard let provider = ProviderKind(rawValue: providerRawValue) else {
            return nil
        }

        return UsageEvent(
            id: id,
            timestamp: timestamp,
            provider: provider,
            model: model,
            usage: TokenUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheHitInputTokens: cacheHitInputTokens,
                cacheMissInputTokens: cacheMissInputTokens
            ),
            costUSD: Decimal(string: costUSDValue) ?? .zero,
            statusCode: statusCode,
            durationMS: durationMS,
            clientLabel: clientLabel,
            isAnomalous: isAnomalous
        )
    }
}

@Model
final class ProviderBalanceEntry {
    var id: UUID
    var providerRawValue: String
    var currency: String
    var totalBalanceValue: String
    var isAvailable: Bool
    var updatedAt: Date

    init(provider: ProviderKind, balance: BalanceSummary) {
        id = UUID()
        providerRawValue = provider.rawValue
        currency = balance.currency
        totalBalanceValue = balance.totalBalance.description
        isAvailable = balance.isAvailable
        updatedAt = balance.updatedAt
    }
}
