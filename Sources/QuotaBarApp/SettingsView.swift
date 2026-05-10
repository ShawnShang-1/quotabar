import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appState: AppState
    @ObservedObject var alertManager: AlertManager

    var body: some View {
        Form {
            Section("DeepSeek") {
                SecureField("API key", text: $appState.deepSeekAPIKeyDraft)

                HStack {
                    Button("Save Key") {
                        appState.saveDeepSeekAPIKey()
                    }
                    .disabled(appState.deepSeekAPIKeyDraft.isEmpty)

                    Button("Delete Key") {
                        appState.deleteDeepSeekAPIKey()
                    }
                    .disabled(!appState.settings.hasDeepSeekAPIKey)

                    Spacer()

                    Text(appState.settings.hasDeepSeekAPIKey ? "Configured" : "Missing")
                        .foregroundStyle(appState.settings.hasDeepSeekAPIKey ? Color.secondary : Color.red)
                }

                HStack {
                    Text("Balance")
                    Spacer()
                    Text(appState.balanceSummary.shortBalanceText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Balance") {
                    Task {
                        await appState.refreshBalance()
                    }
                }
                .disabled(!appState.settings.hasDeepSeekAPIKey)
            }

            Section("Local Proxy") {
                TextField("Port", value: $appState.settings.proxyPort, format: .number)

                TextField("Bearer token", text: $appState.settings.proxyBearerToken)
                    .textSelection(.enabled)

                HStack {
                    Text("Base URL")
                    Spacer()
                    Text(appState.proxyBaseURLText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Start Proxy") {
                        Task {
                            await appState.startProxy()
                        }
                    }
                    .disabled(!appState.settings.hasDeepSeekAPIKey)

                    Button("Stop Proxy") {
                        Task {
                            await appState.stopProxy()
                        }
                    }

                    Spacer()

                    Text(appState.proxyStatus.label)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Budgets & Alerts") {
                TextField(
                    "Daily budget USD",
                    value: $appState.settings.dailyBudgetUSD,
                    format: .number.precision(.fractionLength(2))
                )

                TextField(
                    "Low balance threshold",
                    value: $appState.settings.lowBalanceThreshold,
                    format: .number.precision(.fractionLength(2))
                )

                Slider(
                    value: $appState.settings.spikeMultiplier,
                    in: 1.25...5,
                    step: 0.25
                ) {
                    Text("Spike multiplier")
                } minimumValueLabel: {
                    Text("1.25x")
                } maximumValueLabel: {
                    Text("5x")
                }

                Toggle("Usage notifications", isOn: $appState.settings.notificationsEnabled)

                HStack {
                    Text("Permission")
                    Spacer()
                    Text(notificationStateText)
                        .foregroundStyle(.secondary)
                }

                Button("Request Permission") {
                    Task {
                        await alertManager.requestAuthorization()
                    }
                }
                .disabled(alertManager.authorizationState == .authorized)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
                    .disabled(true)
            }

            if let message = appState.lastErrorMessage ?? alertManager.lastErrorMessage {
                Section("Last Error") {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .task {
            appState.attachModelContext(modelContext)
            appState.loadKeyState()
            await alertManager.refreshAuthorizationState()
        }
    }

    private var notificationStateText: String {
        switch alertManager.authorizationState {
        case .unknown:
            "Not requested"
        case .denied:
            "Denied"
        case .authorized:
            "Allowed"
        case .provisional:
            "Provisional"
        }
    }
}

#Preview {
    SettingsView(appState: AppState(), alertManager: AlertManager())
        .modelContainer(for: [UsageLedgerEntry.self, ProviderBalanceEntry.self], inMemory: true)
}
