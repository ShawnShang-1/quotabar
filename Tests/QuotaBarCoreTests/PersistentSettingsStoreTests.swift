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
        launchAtLogin: true,
        deepSeekPricing: DeepSeekPricingCatalog(
            v4Flash: .defaultV4FlashCNY,
            v4Pro: .defaultV4ProCNY
        )
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

@Test func persistentSettingsMigratesOlderSettingsWithoutPricingToDefaultCNYPricing() throws {
    let suiteName = "QuotaBarSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    let store = PersistentSettingsStore(defaults: defaults)
    let legacyJSON = """
    {
      "proxyPort": 3847,
      "proxyBearerToken": "local-token",
      "autoStartProxy": true,
      "refreshIntervalSeconds": 300,
      "dailyBudgetUSD": 5,
      "lowBalanceThreshold": 20,
      "spikeMultiplier": 2,
      "notificationsEnabled": true,
      "launchAtLogin": false
    }
    """
    defaults.set(Data(legacyJSON.utf8), forKey: "quotabar.persistent-settings.v1")

    let settings = try store.load()

    #expect(settings.deepSeekPricing == .defaultCNY)
}
