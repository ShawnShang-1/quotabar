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

                Toggle("Start proxy when QuotaBar opens", isOn: $appState.settings.autoStartProxy)

                HStack {
                    Text("Base URL")
                    Spacer()
                    Text(appState.proxyBaseURLText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                if appState.proxyStatus == .needsRestart {
                    Text("Restart the proxy to apply the new port or bearer token.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Copy URL") {
                        appState.copyProxyBaseURLToPasteboard()
                    }

                    Button("Copy Token") {
                        appState.copyProxyBearerTokenToPasteboard()
                    }
                }

                HStack {
                    Button("Start Proxy") {
                        Task {
                            await appState.startProxy()
                        }
                    }
                    .disabled(!appState.settings.hasDeepSeekAPIKey)

                    Button("Restart") {
                        Task {
                            await appState.restartProxy()
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

                Stepper(
                    "Refresh every \(appState.settings.refreshIntervalSeconds / 60) min",
                    value: $appState.settings.refreshIntervalSeconds,
                    in: 60...3600,
                    step: 60
                )

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

            Section("Ledger") {
                TextField("Model filter", text: $appState.ledgerModelFilter)
                TextField("Client filter", text: $appState.ledgerClientFilter)
                TextField("Status filter, comma-separated", text: $appState.ledgerStatusFilter)

                HStack {
                    Button("Export CSV") {
                        appState.exportLedgerCSV()
                    }

                    Button("Export JSON") {
                        appState.exportLedgerJSON()
                    }

                    Button("Clear Ledger", role: .destructive) {
                        appState.clearLedger()
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
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
            await appState.bootstrap()
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
