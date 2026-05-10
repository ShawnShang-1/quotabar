import Foundation

public enum PersistentSettingsStoreError: Error, Equatable, Sendable {
    case invalidStoredData
}

public struct PersistentQuotaSettings: Codable, Equatable, Sendable {
    public var proxyPort: Int
    public var proxyBearerToken: String
    public var autoStartProxy: Bool
    public var refreshIntervalSeconds: Int
    public var dailyBudgetUSD: Decimal
    public var lowBalanceThreshold: Decimal
    public var spikeMultiplier: Double
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool

    public init(
        proxyPort: Int,
        proxyBearerToken: String,
        autoStartProxy: Bool,
        refreshIntervalSeconds: Int,
        dailyBudgetUSD: Decimal,
        lowBalanceThreshold: Decimal,
        spikeMultiplier: Double,
        notificationsEnabled: Bool,
        launchAtLogin: Bool
    ) {
        self.proxyPort = proxyPort
        self.proxyBearerToken = proxyBearerToken
        self.autoStartProxy = autoStartProxy
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.dailyBudgetUSD = dailyBudgetUSD
        self.lowBalanceThreshold = lowBalanceThreshold
        self.spikeMultiplier = spikeMultiplier
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = PersistentQuotaSettings(
        proxyPort: 3847,
        proxyBearerToken: UUID().uuidString,
        autoStartProxy: true,
        refreshIntervalSeconds: 300,
        dailyBudgetUSD: Decimal(string: "5")!,
        lowBalanceThreshold: Decimal(string: "20")!,
        spikeMultiplier: 2,
        notificationsEnabled: true,
        launchAtLogin: false
    )
}

public struct PersistentSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "quotabar.persistent-settings.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> PersistentQuotaSettings {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(PersistentQuotaSettings.self, from: data)
        } catch {
            throw PersistentSettingsStoreError.invalidStoredData
        }
    }

    public func save(_ settings: PersistentQuotaSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
