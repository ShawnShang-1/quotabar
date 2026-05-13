import SwiftUI
import SwiftData

@main
struct QuotaBarApp: App {
    @StateObject private var appState: AppState
    @StateObject private var alertManager = AlertManager()
    private let modelContainer: ModelContainer

    init() {
        let container: ModelContainer
        let containerError: Error?
        do {
            container = try ModelContainer(
                for: UsageLedgerEntry.self,
                ProviderBalanceEntry.self
            )
            containerError = nil
        } catch {
            container = try! ModelContainer(
                for: UsageLedgerEntry.self,
                ProviderBalanceEntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            containerError = error
        }
        modelContainer = container
        let state = AppState()
        if let containerError {
            state.lastErrorMessage = "本地账本加载失败，已临时使用内存账本：\(containerError.localizedDescription)"
        }
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
            VStack(alignment: .trailing, spacing: -1) {
                Text(appState.statusTitleLines[0])
                Text(appState.statusTitleLines[1])
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
                .task {
                    await appState.bootstrap()
                }
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
