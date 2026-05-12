public enum StartupRestorePolicy {
    public static func shouldStartProxy(
        settings: PersistentQuotaSettings,
        hasAPIKey: Bool
    ) -> Bool {
        settings.autoStartProxy && hasAPIKey
    }

    public static func shouldStartProxy(
        settings: PersistentQuotaSettings,
        hasAPIKey: Bool,
        isProxyRunning: Bool
    ) -> Bool {
        shouldStartProxy(settings: settings, hasAPIKey: hasAPIKey) && !isProxyRunning
    }
}
