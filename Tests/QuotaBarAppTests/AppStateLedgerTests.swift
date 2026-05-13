import QuotaBarCore
import SwiftData
import XCTest
@testable import QuotaBarApp

@MainActor
final class AppStateLedgerTests: XCTestCase {
    func testAttachModelContextPersistsPreAttachedUsageEvents() throws {
        let now = Date()
        let event = UsageEvent(
            timestamp: now,
            provider: .deepSeek,
            model: "deepseek-chat",
            usage: TokenUsage(
                inputTokens: 12,
                outputTokens: 7,
                cacheHitInputTokens: 4,
                cacheMissInputTokens: 8
            ),
            costUSD: Decimal(string: "0.0000030912")!,
            statusCode: 200,
            durationMS: 120,
            clientLabel: "codex",
            isAnomalous: false
        )
        let appState = AppState(
            settings: .default,
            memoryEvents: [event]
        )
        let container = try ModelContainer(
            for: UsageLedgerEntry.self,
            ProviderBalanceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        appState.attachModelContext(context)

        XCTAssertEqual(appState.todaySummary.totalTokens, 19)
        XCTAssertEqual(appState.todayByModel.first?.model, "deepseek-v4-flash")
        XCTAssertEqual(appState.todayByModel.first?.totalCostUSD, Decimal(string: "0.0000030912"))
        let persisted = try context.fetch(FetchDescriptor<UsageLedgerEntry>())
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, event.id)
    }

    func testDashboardKeepsFlashAndProRowsEvenWhenOneModelIsUnused() throws {
        let event = UsageEvent(
            timestamp: Date(),
            provider: .deepSeek,
            model: "deepseek-v4-flash[1m]",
            usage: TokenUsage(inputTokens: 100, outputTokens: 20, cacheHitInputTokens: 40),
            costUSD: Decimal(string: "0.12")!,
            statusCode: 200,
            durationMS: 120,
            clientLabel: "cc-switch",
            isAnomalous: false
        )
        let appState = AppState(settings: .default, memoryEvents: [event])

        XCTAssertEqual(appState.todayByModel.map(\.model), ["deepseek-v4-flash", "deepseek-v4-pro"])
        XCTAssertEqual(appState.todayByModel[0].totalTokens, 120)
        XCTAssertEqual(appState.todayByModel[1].totalTokens, 0)
        XCTAssertEqual(appState.todayByModel[1].totalCostUSD, .zero)
    }

    func testAmountsDisplayWithoutCurrencyAndWithTwoFractionDigits() {
        let appState = AppState(
            balanceSummary: BalanceSummary(isAvailable: true, currency: "CNY", totalBalance: Decimal(string: "4.956")!),
            settings: .default,
            memoryEvents: [
                UsageEvent(
                    timestamp: Date(),
                    provider: .deepSeek,
                    model: "deepseek-v4-pro",
                    usage: TokenUsage(inputTokens: 1, outputTokens: 1),
                    costUSD: Decimal(string: "1.9069")!,
                    statusCode: 200,
                    durationMS: 1,
                    clientLabel: nil,
                    isAnomalous: false
                )
            ]
        )

        XCTAssertEqual(Decimal(string: "1.9069")!.amountText, "1.91")
        XCTAssertEqual(appState.balanceSummary.shortBalanceText, "4.96")
        XCTAssertFalse(appState.statusTitle.contains("CNY"))
        XCTAssertFalse(appState.statusTitle.contains("$"))
        XCTAssertTrue(appState.statusTitle.contains("4.96"))
        XCTAssertTrue(appState.statusTitle.contains("1.91"))
        XCTAssertEqual(appState.statusTitleLines, ["4.96", "1.91"])
    }

    func testUsageTrendCoversPastThirtyDaysThroughToday() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twentyNineDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -29, to: today))
        let thirtyDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: today))
        let appState = AppState(
            settings: .default,
            memoryEvents: [
                UsageEvent(
                    timestamp: twentyNineDaysAgo.addingTimeInterval(60),
                    provider: .deepSeek,
                    model: "deepseek-v4-flash",
                    usage: TokenUsage(inputTokens: 10, outputTokens: 1),
                    costUSD: Decimal(string: "0.10")!,
                    statusCode: 200,
                    durationMS: 1,
                    clientLabel: nil,
                    isAnomalous: false
                ),
                UsageEvent(
                    timestamp: thirtyDaysAgo.addingTimeInterval(60),
                    provider: .deepSeek,
                    model: "deepseek-v4-pro",
                    usage: TokenUsage(inputTokens: 10, outputTokens: 1),
                    costUSD: Decimal(string: "99")!,
                    statusCode: 200,
                    durationMS: 1,
                    clientLabel: nil,
                    isAnomalous: false
                )
            ]
        )

        XCTAssertEqual(appState.monthlyTrend.count, 30)
        XCTAssertEqual(calendar.startOfDay(for: appState.monthlyTrend.first!.day), twentyNineDaysAgo)
        XCTAssertEqual(calendar.startOfDay(for: appState.monthlyTrend.last!.day), today)
        XCTAssertEqual(appState.monthlyTrend.first?.totalCostUSD, Decimal(string: "0.10")!)
        XCTAssertEqual(appState.monthlyTrend.reduce(Decimal.zero) { $0 + $1.totalCostUSD }, Decimal(string: "0.10")!)
    }

    func testModelBarLayoutKeepsZeroUsageAsThinBar() {
        XCTAssertEqual(TodayModelBarLayout.barFraction(tokens: 0, maxTokens: 0), 0.025)
        XCTAssertEqual(TodayModelBarLayout.barFraction(tokens: 0, maxTokens: 1_000_000), 0.025)
        XCTAssertEqual(TodayModelBarLayout.barFraction(tokens: 500_000, maxTokens: 1_000_000), 0.5)
        XCTAssertEqual(TodayModelBarLayout.barFraction(tokens: 2_000_000, maxTokens: 1_000_000), 1)
    }
}
