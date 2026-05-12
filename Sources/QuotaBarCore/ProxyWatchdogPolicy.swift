public enum ProxyWatchdogPolicy {
    public static func shouldRestartProxy(
        settings: PersistentQuotaSettings,
        hasAPIKey: Bool,
        proxyStatusIsRunning: Bool,
        healthCheckSucceeded: Bool
    ) -> Bool {
        settings.autoStartProxy && hasAPIKey && proxyStatusIsRunning && !healthCheckSucceeded
    }
}
