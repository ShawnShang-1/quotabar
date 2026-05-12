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
}
