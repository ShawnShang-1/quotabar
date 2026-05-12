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
    public var deepSeekPricing: DeepSeekPricingCatalog

    public init(
        proxyPort: Int,
        proxyBearerToken: String,
        autoStartProxy: Bool,
        refreshIntervalSeconds: Int,
        dailyBudgetUSD: Decimal,
        lowBalanceThreshold: Decimal,
        spikeMultiplier: Double,
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        deepSeekPricing: DeepSeekPricingCatalog = .defaultCNY
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
        self.deepSeekPricing = deepSeekPricing
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
        launchAtLogin: false,
        deepSeekPricing: .defaultCNY
    )

    private enum CodingKeys: String, CodingKey {
        case proxyPort
        case proxyBearerToken
        case autoStartProxy
        case refreshIntervalSeconds
        case dailyBudgetUSD
        case lowBalanceThreshold
        case spikeMultiplier
        case notificationsEnabled
        case launchAtLogin
        case deepSeekPricing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proxyPort = try container.decode(Int.self, forKey: .proxyPort)
        proxyBearerToken = try container.decode(String.self, forKey: .proxyBearerToken)
        autoStartProxy = try container.decode(Bool.self, forKey: .autoStartProxy)
        refreshIntervalSeconds = try container.decode(Int.self, forKey: .refreshIntervalSeconds)
        dailyBudgetUSD = try container.decode(Decimal.self, forKey: .dailyBudgetUSD)
        lowBalanceThreshold = try container.decode(Decimal.self, forKey: .lowBalanceThreshold)
        spikeMultiplier = try container.decode(Double.self, forKey: .spikeMultiplier)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        deepSeekPricing = try container.decodeIfPresent(DeepSeekPricingCatalog.self, forKey: .deepSeekPricing) ?? .defaultCNY
    }
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
