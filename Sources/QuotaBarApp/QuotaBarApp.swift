import SwiftUI
import SwiftData

@main
struct QuotaBarApp: App {
    @StateObject private var appState: AppState
    @StateObject private var alertManager = AlertManager()
    private let modelContainer: ModelContainer

    init() {
        let container = try! ModelContainer(
            for: UsageLedgerEntry.self,
            ProviderBalanceEntry.self
        )
        modelContainer = container
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        Task { @MainActor in
            state.attachModelContext(container.mainContext)
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
        .modelContainer(modelContainer)

        Settings {
            SettingsView(appState: appState, alertManager: alertManager)
                .frame(width: 420)
        }
        .modelContainer(modelContainer)
    }
}
