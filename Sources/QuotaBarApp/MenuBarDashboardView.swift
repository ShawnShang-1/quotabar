import Charts
import QuotaBarCore
import SwiftData
import SwiftUI

struct MenuBarDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appState: AppState
    @ObservedObject var alertManager: AlertManager

    private var dailyBudgetProgress: Double {
        guard appState.settings.dailyBudgetUSD > 0 else {
            return 0
        }
        return min(
            appState.todaySummary.totalCostUSD.doubleValue / appState.settings.dailyBudgetUSD.doubleValue,
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ProgressView(value: dailyBudgetProgress) {
                HStack {
                    Text("Daily spend")
                    Spacer()
                    Text("\(appState.todaySummary.totalCostUSD.usdText) / \(appState.settings.dailyBudgetUSD.usdText)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            chartSection(title: "Today by model") {
                Chart(appState.todayByModel) { item in
                    BarMark(
                        x: .value("Tokens", item.totalTokens),
                        y: .value("Model", item.model)
                    )
                    .foregroundStyle(by: .value("Model", item.model))
                    .annotation(position: .trailing, alignment: .leading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.totalTokens, format: .number.notation(.compactName))
                            Text(item.totalCostUSD.usdText)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 3))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 136)
            }

            chartSection(title: "Monthly cost trend") {
                Chart(appState.monthlyTrend) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cost", item.totalCostUSD.doubleValue)
                    )
                    .foregroundStyle(.blue.opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 112)
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 380)
        .task {
            appState.attachModelContext(modelContext)
            await appState.bootstrap()
            await alertManager.refreshAuthorizationState()
            await scheduleCurrentAlerts()
        }
        .onChange(of: appState.todaySummary.totalCostUSD) { _, _ in
            Task {
                await scheduleCurrentAlerts()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QuotaBar")
                    .font(.headline)
                Text(appState.balanceSummary.shortBalanceText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(appState.balanceSummary.isAvailable ? "DeepSeek available" : "DeepSeek unavailable")
                    .font(.caption)
                    .foregroundStyle(appState.balanceSummary.isAvailable ? Color.secondary : Color.red)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Task {
                        await appState.refreshBalance()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh DeepSeek balance")

                Text("Today \(appState.todaySummary.totalCostUSD.usdText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(appState.proxyStatus.label, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }

            Text(appState.proxyBaseURLText)
                .font(.caption2)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            if let message = appState.lastErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func chartSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func scheduleCurrentAlerts() async {
        guard appState.settings.notificationsEnabled else {
            return
        }
        await alertManager.schedule(appState.currentAlertCandidates)
    }
}

#Preview {
    MenuBarDashboardView(appState: AppState(), alertManager: AlertManager())
        .modelContainer(for: [UsageLedgerEntry.self, ProviderBalanceEntry.self], inMemory: true)
}
