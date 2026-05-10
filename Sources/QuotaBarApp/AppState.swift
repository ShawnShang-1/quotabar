import Foundation
import QuotaBarCore
import QuotaBarProxy
import SwiftData
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var balanceSummary: BalanceSummary
    @Published var todaySummary: UsageSummary
    @Published var todayByModel: [UsageModelSummary]
    @Published var monthlyTrend: [DailyUsagePoint]
    @Published var settings: QuotaSettings
    @Published var proxyStatus: ProxyStatus = .stopped
    @Published var deepSeekAPIKeyDraft = ""
    @Published var lastErrorMessage: String?

    private let keychain: KeychainCredentialStore
    private var proxyServer: LocalProxyServer?
    private var modelContext: ModelContext?
    private var memoryEvents: [UsageEvent]

    init(
        keychain: KeychainCredentialStore = KeychainCredentialStore(),
        balanceSummary: BalanceSummary = .preview,
        settings: QuotaSettings = .default,
        memoryEvents: [UsageEvent] = UsageEvent.previewEvents
    ) {
        self.keychain = keychain
        self.balanceSummary = balanceSummary
        self.settings = settings
        self.memoryEvents = memoryEvents
        let initialTodaySummary = UsageAggregator.summary(
            for: memoryEvents,
            interval: Self.todayInterval()
        )
        self.todaySummary = initialTodaySummary
        self.todayByModel = Array(initialTodaySummary.byModel)
        self.monthlyTrend = UsageAggregator.dailyTrend(
            for: memoryEvents,
            interval: Self.monthInterval()
        )
    }

    var statusTitle: String {
        "\(balanceSummary.shortBalanceText) | 今日 \(todaySummary.totalCostUSD.usdText)"
    }

    var proxyBaseURLText: String {
        "http://127.0.0.1:\(settings.proxyPort)/v1"
    }

    var currentAlertCandidates: [UsageAlertCandidate] {
        let events = currentEvents()
        let currentHour = Self.currentHourInterval()
        let previousHours = Self.previousHoursInterval()
        let currentHourCost = events
            .filter { currentHour.contains($0.timestamp) }
            .reduce(Decimal.zero) { $0 + $1.costUSD }
        let previousCost = events
            .filter { previousHours.contains($0.timestamp) }
            .reduce(Decimal.zero) { $0 + $1.costUSD }
        let hourlyBaseline = previousCost / Decimal(24)
        let policy = UsageAlertPolicy(
            lowBalanceThreshold: settings.lowBalanceThreshold,
            dailyBudgetUSD: settings.dailyBudgetUSD,
            spikeMultiplier: settings.spikeMultiplier
        )

        return policy.evaluate(
            balance: ProviderBalanceSnapshot(
                provider: .deepSeek,
                currency: balanceSummary.currency,
                totalBalance: balanceSummary.totalBalance,
                isAvailable: balanceSummary.isAvailable,
                updatedAt: balanceSummary.updatedAt
            ),
            today: todaySummary,
            currentHourCostUSD: currentHourCost,
            hourlyBaselineCostUSD: hourlyBaseline
        )
    }

    func attachModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
        reloadLedger()
    }

    func loadKeyState() {
        do {
            settings.hasDeepSeekAPIKey = try keychain.load(account: KeychainAccount.deepSeekAPIKey) != nil
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveDeepSeekAPIKey() {
        do {
            try keychain.save(deepSeekAPIKeyDraft, account: KeychainAccount.deepSeekAPIKey)
            deepSeekAPIKeyDraft = ""
            settings.hasDeepSeekAPIKey = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteDeepSeekAPIKey() {
        do {
            try keychain.delete(account: KeychainAccount.deepSeekAPIKey)
            settings.hasDeepSeekAPIKey = false
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshBalance() async {
        do {
            let apiKey = try requireDeepSeekAPIKey()
            let balance = try await DeepSeekProvider(apiKey: apiKey).fetchBalance()
            balanceSummary = BalanceSummary(balance: balance, updatedAt: .now)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startProxy() async {
        do {
            let apiKey = try requireDeepSeekAPIKey()
            let provider = DeepSeekProvider(apiKey: apiKey)
            let server = LocalProxyServer(
                configuration: .init(host: "127.0.0.1", port: settings.proxyPort),
                authenticator: ProxyAuthenticator(requiredBearerToken: settings.proxyBearerToken),
                provider: provider,
                usageRecorder: { [weak self] event in
                    await MainActor.run {
                        self?.record(event)
                    }
                }
            )
            let port = try await server.start()
            settings.proxyPort = port
            proxyServer = server
            proxyStatus = .running(port: port)
            lastErrorMessage = nil
        } catch {
            proxyStatus = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopProxy() async {
        await proxyServer?.stop()
        proxyServer = nil
        proxyStatus = .stopped
    }

    func refreshUsageViews() {
        reloadLedger()
    }

    private func record(_ event: UsageEvent) {
        memoryEvents.append(event)
        if let modelContext {
            modelContext.insert(UsageLedgerEntry(event: event))
            try? modelContext.save()
        }
        rebuildSnapshots(from: currentEvents())
    }

    private func reloadLedger() {
        rebuildSnapshots(from: currentEvents())
    }

    private func currentEvents() -> [UsageEvent] {
        guard let modelContext else {
            return memoryEvents
        }

        do {
            let descriptor = FetchDescriptor<UsageLedgerEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let persistedEvents = try modelContext.fetch(descriptor).compactMap(\.usageEvent)
            return persistedEvents.isEmpty ? memoryEvents : persistedEvents
        } catch {
            lastErrorMessage = error.localizedDescription
            return memoryEvents
        }
    }

    private func rebuildSnapshots(from events: [UsageEvent]) {
        let today = UsageAggregator.summary(for: events, interval: Self.todayInterval())
        todaySummary = today
        todayByModel = Array(today.byModel)
        monthlyTrend = UsageAggregator.dailyTrend(for: events, interval: Self.monthInterval())
    }

    private func requireDeepSeekAPIKey() throws -> String {
        guard let apiKey = try keychain.load(account: KeychainAccount.deepSeekAPIKey), !apiKey.isEmpty else {
            throw AppStateError.missingDeepSeekAPIKey
        }
        return apiKey
    }

    private static func todayInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private static func monthInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private static func currentHourInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let start = calendar.date(from: components) ?? now
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private static func previousHoursInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let currentHour = currentHourInterval(now: now, calendar: calendar)
        let start = calendar.date(byAdding: .hour, value: -24, to: currentHour.start) ?? currentHour.start
        return DateInterval(start: start, end: currentHour.start)
    }
}

enum AppStateError: LocalizedError {
    case missingDeepSeekAPIKey

    var errorDescription: String? {
        switch self {
        case .missingDeepSeekAPIKey:
            "DeepSeek API key is not configured."
        }
    }
}

enum KeychainAccount {
    static let deepSeekAPIKey = "deepseek-api-key"
}

enum ProxyStatus: Equatable {
    case stopped
    case running(port: Int)
    case failed(String)

    var label: String {
        switch self {
        case .stopped:
            "Stopped"
        case let .running(port):
            "Running on \(port)"
        case .failed:
            "Failed"
        }
    }
}

struct BalanceSummary: Equatable {
    var isAvailable: Bool
    var currency: String
    var totalBalance: Decimal
    var updatedAt: Date

    init(isAvailable: Bool, currency: String, totalBalance: Decimal, updatedAt: Date = .now) {
        self.isAvailable = isAvailable
        self.currency = currency
        self.totalBalance = totalBalance
        self.updatedAt = updatedAt
    }

    init(balance: DeepSeekBalance, updatedAt: Date) {
        self.init(
            isAvailable: balance.isAvailable,
            currency: balance.primaryCurrency ?? "CNY",
            totalBalance: balance.primaryTotalBalance ?? .zero,
            updatedAt: updatedAt
        )
    }

    var shortBalanceText: String {
        "\(currency) \(totalBalance.shortDecimalText)"
    }

    static let preview = BalanceSummary(
        isAvailable: true,
        currency: "CNY",
        totalBalance: Decimal(string: "110.93")!
    )
}

struct QuotaSettings: Equatable {
    var dailyBudgetUSD: Decimal
    var lowBalanceThreshold: Decimal
    var spikeMultiplier: Double
    var notificationsEnabled: Bool
    var launchAtLogin: Bool
    var proxyPort: Int
    var proxyBearerToken: String
    var hasDeepSeekAPIKey: Bool

    static let `default` = QuotaSettings(
        dailyBudgetUSD: Decimal(string: "5")!,
        lowBalanceThreshold: Decimal(string: "20")!,
        spikeMultiplier: 2,
        notificationsEnabled: true,
        launchAtLogin: false,
        proxyPort: 3847,
        proxyBearerToken: UUID().uuidString,
        hasDeepSeekAPIKey: false
    )
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    var usdText: String {
        "$\(shortDecimalText)"
    }

    var shortDecimalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}

private extension UsageEvent {
    static var previewEvents: [UsageEvent] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        return [
            UsageEvent(
                timestamp: todayStart.addingTimeInterval(60 * 18),
                provider: .deepSeek,
                model: "deepseek-chat",
                usage: TokenUsage(inputTokens: 120_000, outputTokens: 18_000, cacheHitInputTokens: 80_000, cacheMissInputTokens: 40_000),
                costUSD: Decimal(string: "0.00872")!,
                statusCode: 200,
                durationMS: 430,
                clientLabel: "codex",
                isAnomalous: false
            ),
            UsageEvent(
                timestamp: todayStart.addingTimeInterval(60 * 60 * 4),
                provider: .deepSeek,
                model: "deepseek-reasoner",
                usage: TokenUsage(inputTokens: 300_000, outputTokens: 42_000, cacheHitInputTokens: 210_000, cacheMissInputTokens: 90_000),
                costUSD: Decimal(string: "0.02448")!,
                statusCode: 200,
                durationMS: 1_220,
                clientLabel: "editor",
                isAnomalous: false
            )
        ] + (1..<18).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            return UsageEvent(
                timestamp: day.addingTimeInterval(60 * 60 * 8),
                provider: .deepSeek,
                model: offset.isMultiple(of: 3) ? "deepseek-reasoner" : "deepseek-chat",
                usage: TokenUsage(inputTokens: 40_000 + offset * 1_200, outputTokens: 8_000 + offset * 500),
                costUSD: Decimal(Double(offset) * 0.006 + 0.02),
                statusCode: 200,
                durationMS: 380 + offset * 10,
                clientLabel: nil,
                isAnomalous: false
            )
        }
    }
}
