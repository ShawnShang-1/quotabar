public enum StartupRestorePolicy {
    public static func shouldStartProxy(
        settings: PersistentQuotaSettings,
        hasAPIKey: Bool
    ) -> Bool {
        settings.autoStartProxy && hasAPIKey
    }
}
