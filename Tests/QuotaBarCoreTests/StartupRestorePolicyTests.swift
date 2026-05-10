import Testing
@testable import QuotaBarCore

@Test func startupRestoreStartsOnlyWhenEnabledAndKeyExists() {
    #expect(StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: true))
    #expect(!StartupRestorePolicy.shouldStartProxy(settings: .default, hasAPIKey: false))

    var disabled = PersistentQuotaSettings.default
    disabled.autoStartProxy = false

    #expect(!StartupRestorePolicy.shouldStartProxy(settings: disabled, hasAPIKey: true))
}
