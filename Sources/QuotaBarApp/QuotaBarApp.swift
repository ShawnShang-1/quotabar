import SwiftUI
import SwiftData

@main
struct QuotaBarApp: App {
    @StateObject private var appState: AppState
    @StateObject private var alertManager = AlertManager()

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        Task { @MainActor in
            await state.bootstrap()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarDashboardView(appState: appState, alertManager: alertManager)
        } label: {
            Label(appState.statusTitle, systemImage: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: [
            UsageLedgerEntry.self,
            ProviderBalanceEntry.self
        ])

        Settings {
            SettingsView(appState: appState, alertManager: alertManager)
                .frame(width: 420)
        }
        .modelContainer(for: [
            UsageLedgerEntry.self,
            ProviderBalanceEntry.self
        ])
    }
}
