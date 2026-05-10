import Foundation
import QuotaBarCore
import UserNotifications

@MainActor
final class AlertManager: ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case denied
        case authorized
        case provisional
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var lastErrorMessage: String?

    private let notificationCenter: UNUserNotificationCenter?
    private var sentIdentifiers = Set<String>()

    init(notificationCenter: UNUserNotificationCenter? = nil) {
        if let notificationCenter {
            self.notificationCenter = notificationCenter
        } else if Bundle.main.bundleIdentifier == nil {
            self.notificationCenter = nil
        } else {
            self.notificationCenter = .current()
        }
    }

    func refreshAuthorizationState() async {
        guard let notificationCenter else {
            authorizationState = .denied
            lastErrorMessage = "Notifications require running QuotaBar as an app bundle."
            return
        }

        let settings = await notificationCenter.notificationSettings()
        authorizationState = AuthorizationState(settings.authorizationStatus)
    }

    func requestAuthorization() async {
        guard let notificationCenter else {
            authorizationState = .denied
            lastErrorMessage = "Notifications require running QuotaBar as an app bundle."
            return
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            authorizationState = granted ? .authorized : .denied
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            await refreshAuthorizationState()
        }
    }

    func scheduleUsageAlert(
        title: String,
        body: String,
        identifier: String = "quotabar.usage-alert"
    ) async {
        guard let notificationCenter else {
            lastErrorMessage = "Notifications require running QuotaBar as an app bundle."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func schedule(_ alert: UsageAlertCandidate) async {
        guard !sentIdentifiers.contains(alert.id) else {
            return
        }

        await scheduleUsageAlert(
            title: alert.title,
            body: alert.body,
            identifier: alert.id
        )
        sentIdentifiers.insert(alert.id)
    }

    func schedule(_ alerts: [UsageAlertCandidate]) async {
        for alert in alerts {
            await schedule(alert)
        }
    }

    func removePendingAlerts() {
        notificationCenter?.removePendingNotificationRequests(withIdentifiers: Array(sentIdentifiers) + ["quotabar.usage-alert"])
        sentIdentifiers.removeAll()
    }
}

private extension AlertManager.AuthorizationState {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .provisional, .ephemeral:
            self = .provisional
        case .denied:
            self = .denied
        case .notDetermined:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}
