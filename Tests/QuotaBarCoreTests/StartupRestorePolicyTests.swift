import Testing
@testable import QuotaBarCore

@Test func startupRestoreStartsOnlyWhenEnabledAndKeyExists() {
    #expect(StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: true))
    #expect(!StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: false))

    var disabled = PersistentQuotaSettings.default
    disabled.autoStartProxy = false

    #expect(!StartupRestorePolicy.shouldStartProxy(settings: disabled, hasAPIKey: true))
}

@Test func startupRestoreRetriesWhenProxyIsStoppedOrFailed() {
    #expect(StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: true, isProxyRunning: false))
    #expect(!StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: true, isProxyRunning: true))
    #expect(!StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: false, isProxyRunning: false))
}
