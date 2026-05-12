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

    private var monthTotalTokens: Int {
        appState.monthlyTrend.reduce(0) { $0 + $1.totalTokens }
    }

    private var monthTotalCostUSD: Decimal {
        appState.monthlyTrend.reduce(Decimal.zero) { $0 + $1.totalCostUSD }
    }

    private var monthChartYMax: Double {
        max(1, appState.monthlyTrend.map { $0.totalCostUSD.doubleValue }.max() ?? 0)
    }

    private var maxModelTokens: Int {
        max(1, appState.todayByModel.map(\.totalTokens).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ProgressView(value: dailyBudgetProgress) {
                HStack {
                    Text("Daily spend")
                    Spacer()
                    Text("\(appState.todaySummary.totalCostUSD.amountText) / \(appState.settings.dailyBudgetUSD.amountText)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            chartSection(title: "Today by model") {
                Chart(appState.todayByModel) { item in
                    BarMark(
                        x: .value("Tokens", displayTokens(for: item)),
                        y: .value("Model", item.model)
                    )
                    .foregroundStyle(color(for: item.model))
                    .annotation(position: .trailing, alignment: .leading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.totalTokens, format: .number.notation(.compactName))
                            Text(item.totalCostUSD.amountText)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .chartXScale(domain: 0...Double(max(maxModelTokens, 1)))
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
                Text("30d \(monthTotalCostUSD.amountText) · \(monthTotalTokens.formatted(.number.notation(.compactName))) tok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Chart(appState.monthlyTrend) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cost", item.totalCostUSD.doubleValue)
                    )
                    .foregroundStyle(.blue.opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0...monthChartYMax)
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
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
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

                Text("Today \(appState.todaySummary.totalCostUSD.amountText) · \(appState.todaySummary.totalTokens.formatted(.number.notation(.compactName))) tok")
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
                    Label("设置", systemImage: "gearshape")
                }

                Button("退出") {
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

    private func displayTokens(for item: UsageModelSummary) -> Double {
        if item.totalTokens > 0 {
            return Double(item.totalTokens)
        }
        return max(1, Double(maxModelTokens) * 0.025)
    }

    private func color(for model: String) -> Color {
        switch model {
        case DisplayModel.flash.rawValue:
            Color(red: 0.18, green: 0.78, blue: 0.92)
        case DisplayModel.pro.rawValue:
            Color(red: 0.95, green: 0.56, blue: 0.18)
        default:
            .secondary
        }
    }
}

#Preview {
    MenuBarDashboardView(appState: AppState(), alertManager: AlertManager())
        .modelContainer(for: [UsageLedgerEntry.self, ProviderBalanceEntry.self], inMemory: true)
}
