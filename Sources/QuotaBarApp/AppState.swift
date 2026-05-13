import Foundation
import AppKit
import QuotaBarCore
import QuotaBarProxy
import ServiceManagement
import SwiftData
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var balanceSummary: BalanceSummary
    @Published var todaySummary: UsageSummary
    @Published var todayByModel: [UsageModelSummary]
    @Published var monthlyTrend: [DailyUsagePoint]
    @Published var settings: QuotaSettings {
        didSet {
            persistSettings()
            if hasBootstrapped, oldValue.refreshIntervalSeconds != settings.refreshIntervalSeconds {
                startBalanceRefreshTimer()
            }
            if hasBootstrapped, oldValue.launchAtLogin != settings.launchAtLogin {
                applyLaunchAtLogin(settings.launchAtLogin)
            }
            if hasBootstrapped, proxyStatus.isRunning,
               oldValue.proxyPort != settings.proxyPort
                || oldValue.proxyBearerToken != settings.proxyBearerToken
                || oldValue.deepSeekPricing != settings.deepSeekPricing {
                proxyStatus = .needsRestart
            }
            if hasBootstrapped, !oldValue.autoStartProxy, settings.autoStartProxy {
                Task {
                    await ensureAutoStartedProxyIfNeeded()
                }
            }
            if hasBootstrapped, oldValue.autoStartProxy != settings.autoStartProxy {
                startProxyWatchdogTimer()
            }
        }
    }
    @Published var proxyStatus: ProxyStatus = .stopped
    @Published var deepSeekAPIKeyDraft = ""
    @Published var lastErrorMessage: String?
    @Published var ledgerModelFilter = ""
    @Published var ledgerClientFilter = ""
    @Published var ledgerStatusFilter = ""

    private let keychain: KeychainCredentialStore
    private let settingsStore: PersistentSettingsStore
    private var proxyServer: LocalProxyServer?
    private var modelContext: ModelContext?
    private var memoryEvents: [UsageEvent]
    private var refreshTask: Task<Void, Never>?
    private var usageRolloverTask: Task<Void, Never>?
    private var proxyWatchdogTask: Task<Void, Never>?
    private var isStartingProxy = false
    private var hasBootstrapped = false

    init(
        keychain: KeychainCredentialStore = KeychainCredentialStore(),
        settingsStore: PersistentSettingsStore = PersistentSettingsStore(),
        balanceSummary: BalanceSummary = .preview,
        settings: QuotaSettings? = nil,
        memoryEvents: [UsageEvent] = []
    ) {
        self.keychain = keychain
        self.settingsStore = settingsStore
        self.balanceSummary = balanceSummary
        if let settings {
            self.settings = settings
        } else if let persisted = try? settingsStore.load() {
            self.settings = QuotaSettings(persistent: persisted)
        } else {
            self.settings = .default
        }
        self.memoryEvents = memoryEvents
        let initialTodaySummary = UsageAggregator.summary(
            for: Self.dashboardEvents(from: memoryEvents),
            interval: Self.todayInterval()
        )
        self.todaySummary = initialTodaySummary
        self.todayByModel = Self.displayModelRows(from: initialTodaySummary)
        self.monthlyTrend = UsageAggregator.dailyTrend(
            for: Self.dashboardEvents(from: memoryEvents),
            interval: Self.trailingThirtyDaysInterval()
        )
    }

    deinit {
        refreshTask?.cancel()
        usageRolloverTask?.cancel()
        proxyWatchdogTask?.cancel()
    }

    var statusTitle: String {
        "\(balanceSummary.shortBalanceText) | \(todaySummary.totalCostUSD.amountText)"
    }

    var statusTitleLines: [String] {
        [
            balanceSummary.shortBalanceText,
            todaySummary.totalCostUSD.amountText
        ]
    }

    var proxyBaseURLText: String {
        "http://127.0.0.1:\(settings.proxyPort)/v1"
    }

    var currentAlertCandidates: [UsageAlertCandidate] {
        let events = dashboardEvents()
        let currentHour = Self.currentHourInterval()
        let previousHours = Self.previousHoursInterval()
        let currentHourCost = events
            .filter { currentHour.contains($0.timestamp) }
            .reduce(Decimal.zero) { $0 + $1.normalizedCost }
        let previousCost = events
            .filter { previousHours.contains($0.timestamp) }
            .reduce(Decimal.zero) { $0 + $1.normalizedCost }
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
        flushMemoryEventsToLedgerIfNeeded()
        reloadLedger()
    }

    func bootstrap() async {
        let shouldRefreshStartupBalance = !hasBootstrapped
        hasBootstrapped = true
        loadKeyState()
        startUsageRolloverTimer()
        startProxyWatchdogTimer()
        await ensureAutoStartedProxyIfNeeded()
        if settings.hasDeepSeekAPIKey {
            if shouldRefreshStartupBalance {
                await refreshBalance()
            }
            startBalanceRefreshTimer()
        }
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
            startBalanceRefreshTimer()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteDeepSeekAPIKey() {
        do {
            try keychain.delete(account: KeychainAccount.deepSeekAPIKey)
            settings.hasDeepSeekAPIKey = false
            refreshTask?.cancel()
            refreshTask = nil
            Task {
                await stopProxy()
            }
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
        guard !isStartingProxy else {
            return
        }
        isStartingProxy = true
        defer {
            isStartingProxy = false
        }

        do {
            let apiKey = try requireDeepSeekAPIKey()
            await proxyServer?.stop()
            let provider = DeepSeekProvider(apiKey: apiKey)
            let pricing = settings.deepSeekPricing
            let server = LocalProxyServer(
                configuration: .init(host: "127.0.0.1", port: settings.proxyPort),
                authenticator: ProxyAuthenticator(requiredBearerToken: settings.proxyBearerToken),
                provider: provider,
                costEstimator: { model, usage, _ in
                    try pricing.estimateCostUSD(model: model, usage: usage)
                },
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
            startProxyWatchdogTimer()
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

    func restartProxy() async {
        await stopProxy()
        await startProxy()
    }

    func ensureAutoStartedProxyIfNeeded() async {
        guard StartupRestorePolicy.shouldStartProxy(
            settings: settings.persistentSettings,
            hasAPIKey: settings.hasDeepSeekAPIKey,
            isProxyRunning: proxyStatus.isRunning
        ) else {
            return
        }
        await startProxy()
    }

    func refreshUsageViews() {
        reloadLedger()
    }

    func clearLedger() {
        memoryEvents.removeAll()
        guard let modelContext else {
            rebuildSnapshots(from: [])
            return
        }

        do {
            let entries = try modelContext.fetch(FetchDescriptor<UsageLedgerEntry>())
            for entry in entries {
                modelContext.delete(entry)
            }
            try modelContext.save()
            rebuildSnapshots(from: [])
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportLedgerCSV() {
        exportLedger(suggestedName: "quotabar-ledger.csv") { events in
            Data(try UsageLedgerExporter.exportCSV(events).utf8)
        }
    }

    func exportLedgerJSON() {
        exportLedger(suggestedName: "quotabar-ledger.json") { events in
            try UsageLedgerExporter.exportJSON(events)
        }
    }

    func copyProxyBaseURLToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxyBaseURLText, forType: .string)
    }

    func copyProxyBearerTokenToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.proxyBearerToken, forType: .string)
    }

    private func record(_ event: UsageEvent) {
        if let modelContext {
            do {
                modelContext.insert(UsageLedgerEntry(event: event))
                try modelContext.save()
            } catch {
                memoryEvents.append(event)
                lastErrorMessage = error.localizedDescription
            }
        } else {
            memoryEvents.append(event)
        }
        rebuildSnapshots(from: dashboardEvents())
    }

    private func reloadLedger() {
        rebuildSnapshots(from: dashboardEvents())
    }

    private func flushMemoryEventsToLedgerIfNeeded() {
        guard let modelContext, !memoryEvents.isEmpty else {
            return
        }

        do {
            let persistedEntries = try modelContext.fetch(FetchDescriptor<UsageLedgerEntry>())
            let persistedIDs = Set(persistedEntries.map(\.id))
            for event in memoryEvents where !persistedIDs.contains(event.id) {
                modelContext.insert(UsageLedgerEntry(event: event))
            }
            try modelContext.save()
            memoryEvents.removeAll()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
            let persistedIDs = Set(persistedEvents.map(\.id))
            let pendingEvents = memoryEvents.filter { !persistedIDs.contains($0.id) }
            return persistedEvents + pendingEvents
        } catch {
            lastErrorMessage = error.localizedDescription
            return memoryEvents
        }
    }

    private func dashboardEvents() -> [UsageEvent] {
        let cutoff = Self.dashboardCutoff()
        guard let modelContext else {
            return Self.dashboardEvents(from: memoryEvents)
        }

        do {
            let descriptor = FetchDescriptor<UsageLedgerEntry>(
                predicate: #Predicate { entry in
                    entry.timestamp >= cutoff
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let persistedEvents = try modelContext.fetch(descriptor).compactMap(\.usageEvent)
            let persistedIDs = Set(persistedEvents.map(\.id))
            let pendingEvents = memoryEvents.filter {
                $0.timestamp >= cutoff && !persistedIDs.contains($0.id)
            }
            return persistedEvents + pendingEvents
        } catch {
            lastErrorMessage = error.localizedDescription
            return Self.dashboardEvents(from: memoryEvents)
        }
    }

    private func rebuildSnapshots(from events: [UsageEvent]) {
        let today = UsageAggregator.summary(for: events, interval: Self.todayInterval())
        todaySummary = today
        todayByModel = Self.displayModelRows(from: today)
        monthlyTrend = UsageAggregator.dailyTrend(for: events, interval: Self.trailingThirtyDaysInterval())
    }

    private static func displayModelRows(from summary: UsageSummary) -> [UsageModelSummary] {
        DisplayModel.allCases.map { displayModel in
            summary.byModel[displayModel.rawValue] ?? UsageModelSummary(
                model: displayModel.rawValue,
                inputTokens: 0,
                outputTokens: 0,
                totalCostUSD: .zero
            )
        }
    }

    private func requireDeepSeekAPIKey() throws -> String {
        guard let apiKey = try keychain.load(account: KeychainAccount.deepSeekAPIKey), !apiKey.isEmpty else {
            throw AppStateError.missingDeepSeekAPIKey
        }
        return apiKey
    }

    private func exportLedger(
        suggestedName: String,
        writer: ([UsageEvent]) throws -> Data
    ) {
        let events = UsageLedgerExporter.filter(currentEvents(), query: ledgerQuery)
        do {
            let data = try writer(events)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private var ledgerQuery: UsageLedgerQuery {
        let statusTokens = ledgerStatusFilter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let statusCodes = statusTokens.compactMap(Int.init)
        if !statusTokens.isEmpty, statusCodes.count != statusTokens.count {
            lastErrorMessage = "Status filter must contain only numeric HTTP status codes."
        }

        return UsageLedgerQuery(
            models: ledgerModelFilter.isEmpty ? [] : [ledgerModelFilter],
            clientLabels: ledgerClientFilter.isEmpty ? [] : [ledgerClientFilter],
            statusCodes: Set(statusCodes)
        )
    }

    private func persistSettings() {
        do {
            try settingsStore.save(settings.persistentSettings)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startBalanceRefreshTimer() {
        guard settings.hasDeepSeekAPIKey else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }
        refreshTask?.cancel()
        let interval = max(settings.refreshIntervalSeconds, 60)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else {
                    return
                }
                await self?.refreshBalance()
            }
        }
    }

    private func startUsageRolloverTimer() {
        guard usageRolloverTask == nil else {
            return
        }
        usageRolloverTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = CalendarRefreshPolicy.secondsUntilNextDay(from: .now)
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.refreshUsageViews()
                }
            }
        }
    }

    private func startProxyWatchdogTimer() {
        proxyWatchdogTask?.cancel()
        guard settings.autoStartProxy else {
            proxyWatchdogTask = nil
            return
        }
        proxyWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else {
                    return
                }
                await self?.recoverProxyIfNeeded()
            }
        }
    }

    private func recoverProxyIfNeeded() async {
        let healthCheckSucceeded = await proxyHealthCheck()
        guard ProxyWatchdogPolicy.shouldRestartProxy(
            settings: settings.persistentSettings,
            hasAPIKey: settings.hasDeepSeekAPIKey,
            proxyStatusIsRunning: proxyStatus.isRunning,
            healthCheckSucceeded: healthCheckSucceeded
        ) else {
            return
        }
        await restartProxy()
    }

    private func proxyHealthCheck() async -> Bool {
        guard proxyStatus.isRunning, let url = URL(string: proxyBaseURLText) else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func todayInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private static func trailingThirtyDaysInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateInterval(start: start, end: end)
    }

    private static func dashboardCutoff(now: Date = .now, calendar: Calendar = .current) -> Date {
        trailingThirtyDaysInterval(now: now, calendar: calendar).start
    }

    private static func dashboardEvents(
        from events: [UsageEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [UsageEvent] {
        let cutoff = dashboardCutoff(now: now, calendar: calendar)
        return events.filter { $0.timestamp >= cutoff }
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

enum DisplayModel: String, CaseIterable {
    case flash = "deepseek-v4-flash"
    case pro = "deepseek-v4-pro"

    var title: String {
        rawValue
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
    case needsRestart
    case failed(String)

    var label: String {
        switch self {
        case .stopped:
            "已停止"
        case let .running(port):
            "运行于 \(port)"
        case .needsRestart:
            "需要重启"
        case .failed:
            "启动失败"
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
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
        totalBalance.amountText
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
    var autoStartProxy: Bool
    var refreshIntervalSeconds: Int
    var hasDeepSeekAPIKey: Bool
    var deepSeekPricing: DeepSeekPricingCatalog

    init(
        dailyBudgetUSD: Decimal,
        lowBalanceThreshold: Decimal,
        spikeMultiplier: Double,
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        proxyPort: Int,
        proxyBearerToken: String,
        autoStartProxy: Bool,
        refreshIntervalSeconds: Int,
        hasDeepSeekAPIKey: Bool,
        deepSeekPricing: DeepSeekPricingCatalog
    ) {
        self.dailyBudgetUSD = dailyBudgetUSD
        self.lowBalanceThreshold = lowBalanceThreshold
        self.spikeMultiplier = spikeMultiplier
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.proxyPort = proxyPort
        self.proxyBearerToken = proxyBearerToken
        self.autoStartProxy = autoStartProxy
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.hasDeepSeekAPIKey = hasDeepSeekAPIKey
        self.deepSeekPricing = deepSeekPricing
    }

    init(persistent: PersistentQuotaSettings, hasDeepSeekAPIKey: Bool = false) {
        dailyBudgetUSD = persistent.dailyBudgetUSD
        lowBalanceThreshold = persistent.lowBalanceThreshold
        spikeMultiplier = persistent.spikeMultiplier
        notificationsEnabled = persistent.notificationsEnabled
        launchAtLogin = persistent.launchAtLogin
        proxyPort = persistent.proxyPort
        proxyBearerToken = persistent.proxyBearerToken
        autoStartProxy = persistent.autoStartProxy
        refreshIntervalSeconds = persistent.refreshIntervalSeconds
        self.hasDeepSeekAPIKey = hasDeepSeekAPIKey
        deepSeekPricing = persistent.deepSeekPricing
    }

    static let `default` = QuotaSettings(
        dailyBudgetUSD: Decimal(string: "5")!,
        lowBalanceThreshold: Decimal(string: "20")!,
        spikeMultiplier: 2,
        notificationsEnabled: true,
        launchAtLogin: false,
        proxyPort: 3847,
        proxyBearerToken: UUID().uuidString,
        autoStartProxy: true,
        refreshIntervalSeconds: 300,
        hasDeepSeekAPIKey: false,
        deepSeekPricing: .defaultCNY
    )

    var persistentSettings: PersistentQuotaSettings {
        PersistentQuotaSettings(
            proxyPort: proxyPort,
            proxyBearerToken: proxyBearerToken,
            autoStartProxy: autoStartProxy,
            refreshIntervalSeconds: refreshIntervalSeconds,
            dailyBudgetUSD: dailyBudgetUSD,
            lowBalanceThreshold: lowBalanceThreshold,
            spikeMultiplier: spikeMultiplier,
            notificationsEnabled: notificationsEnabled,
            launchAtLogin: launchAtLogin,
            deepSeekPricing: deepSeekPricing
        )
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    var amountText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
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
    var normalizedCost: Decimal {
        costUSD < .zero ? -costUSD : costUSD
    }

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
