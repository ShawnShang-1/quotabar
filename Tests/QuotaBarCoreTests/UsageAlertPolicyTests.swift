import Foundation
import Testing
@testable import QuotaBarCore

@Test func alertPolicyFlagsLowBalanceAndDailyBudget() {
    let policy = UsageAlertPolicy(
        lowBalanceThreshold: Decimal(string: "20")!,
        dailyBudgetUSD: Decimal(string: "5")!,
        spikeMultiplier: 2
    )
    let balance = ProviderBalanceSnapshot(
        provider: .deepSeek,
        currency: "CNY",
        totalBalance: Decimal(string: "12.5")!,
        isAvailable: true,
        updatedAt: .now
    )
    let today = UsageSummary(
        totalTokens: 10_000,
        totalCostUSD: Decimal(string: "6.2")!,
        byModel: ModelBreakdown([])
    )

    let alerts = policy.evaluate(
        balance: balance,
        today: today,
        currentHourCostUSD: Decimal(string: "0.1")!,
        hourlyBaselineCostUSD: Decimal(string: "0.2")!
    )

    #expect(alerts.map(\.kind) == [.lowBalance, .dailyBudgetExceeded])
}

@Test func alertPolicyFlagsHourlySpikeAgainstBaseline() {
    let policy = UsageAlertPolicy(
        lowBalanceThreshold: Decimal(string: "20")!,
        dailyBudgetUSD: Decimal(string: "5")!,
        spikeMultiplier: 2
    )

    let alerts = policy.evaluate(
        balance: nil,
        today: UsageSummary(totalTokens: 0, totalCostUSD: .zero, byModel: ModelBreakdown([])),
        currentHourCostUSD: Decimal(string: "1.1")!,
        hourlyBaselineCostUSD: Decimal(string: "0.5")!
    )

    #expect(alerts.map(\.kind) == [.usageSpike])
}
