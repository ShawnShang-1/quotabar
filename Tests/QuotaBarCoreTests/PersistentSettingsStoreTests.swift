import Foundation
import Testing
@testable import QuotaBarCore

@Test func persistentSettingsRoundTripPreservesProxyAndBudgetValues() throws {
    let suiteName = "QuotaBarSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    let store = PersistentSettingsStore(defaults: defaults)
    let settings = PersistentQuotaSettings(
        proxyPort: 4455,
        proxyBearerToken: "local-token",
        autoStartProxy: true,
        refreshIntervalSeconds: 180,
        dailyBudgetUSD: Decimal(string: "7.50")!,
        lowBalanceThreshold: Decimal(string: "12.25")!,
        spikeMultiplier: 2.5,
        notificationsEnabled: false,
        launchAtLogin: true
    )

    try store.save(settings)

    #expect(try store.load() == settings)
}

@Test func persistentSettingsReturnsDefaultWhenEmpty() throws {
    let suiteName = "QuotaBarSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    let store = PersistentSettingsStore(defaults: defaults)

    #expect(try store.load() == .default)
}
