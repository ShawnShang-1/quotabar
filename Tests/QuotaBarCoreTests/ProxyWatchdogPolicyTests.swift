import Testing
@testable import QuotaBarCore

@Test func proxyWatchdogRestartsOnlyWhenAutoStartKeyAndExpectedRunningStateArePresent() {
    #expect(
        ProxyWatchdogPolicy.shouldRestartProxy(
            settings: .default,
            hasAPIKey: true,
            proxyStatusIsRunning: true,
            healthCheckSucceeded: false
        )
    )
    #expect(
        !ProxyWatchdogPolicy.shouldRestartProxy(
            settings: .default,
            hasAPIKey: true,
            proxyStatusIsRunning: true,
            healthCheckSucceeded: true
        )
    )
    #expect(
        !ProxyWatchdogPolicy.shouldRestartProxy(
            settings: .default,
            hasAPIKey: false,
            proxyStatusIsRunning: true,
            healthCheckSucceeded: false
        )
    )
}
