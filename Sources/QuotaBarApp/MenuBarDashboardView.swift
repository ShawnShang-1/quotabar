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
        appState.todayByModel.map(\.totalTokens).max() ?? 0
    }

    private var modelTokenCapacity: Int {
        TodayModelBarLayout.capacity(for: maxModelTokens)
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
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.todayByModel) { item in
                        TodayModelBarRow(
                            item: item,
                            capacity: modelTokenCapacity,
                            tint: color(for: item.model),
                            outputTint: outputColor(for: item.model)
                        )
                    }
                }
                .frame(height: 162, alignment: .center)
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

    private func outputColor(for model: String) -> Color {
        switch model {
        case DisplayModel.flash.rawValue:
            Color(red: 0.10, green: 0.50, blue: 0.98)
        case DisplayModel.pro.rawValue:
            Color(red: 1.00, green: 0.34, blue: 0.18)
        default:
            .primary
        }
    }
}

struct TodayModelBarRow: View {
    var item: UsageModelSummary
    var capacity: Int
    var tint: Color
    var outputTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.model)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                GeometryReader { proxy in
                    let segments = TodayModelBarLayout.segments(
                        inputTokens: item.inputTokens,
                        outputTokens: item.outputTokens,
                        capacity: capacity
                    )
                    let totalWidth = max(2, proxy.size.width * segments.totalFraction)
                    let totalTokens = max(0, item.inputTokens + item.outputTokens)
                    let inputShare = totalTokens > 0 ? Double(item.inputTokens) / Double(totalTokens) : 1
                    let inputWidth = totalWidth * inputShare
                    let outputWidth = totalWidth - inputWidth
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.10))
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(tint)
                                .frame(width: inputWidth)
                            Rectangle()
                                .fill(outputTint)
                                .frame(width: outputWidth)
                        }
                        .frame(width: totalWidth, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(height: 30)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(item.totalTokens, format: .number.notation(.compactName))
                    Text(item.totalCostUSD.amountText)
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: TodayModelBarLayout.valueColumnMinWidth, alignment: .trailing)
            }

            HStack(spacing: 8) {
                legendItem(color: tint, label: "in \(item.inputTokens.formatted(.number.notation(.compactName)))")
                legendItem(color: outputTint, label: "out \(item.outputTokens.formatted(.number.notation(.compactName)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }
}

enum TodayModelBarLayout {
    static let zeroFraction = 0.025
    static let valueColumnMinWidth: CGFloat = 0
    private static let tiers = [1_000_000, 10_000_000, 30_000_000, 100_000_000]

    struct Segments: Equatable {
        var inputFraction: Double
        var outputFraction: Double
        var totalFraction: Double
    }

    static func capacity(for maxTokens: Int) -> Int {
        let tokens = max(0, maxTokens)
        if let tier = tiers.first(where: { tokens <= $0 }) {
            return tier
        }
        let step = tiers.last ?? 100_000_000
        return Int(ceil(Double(tokens) / Double(step))) * step
    }

    static func barFraction(tokens: Int, maxTokens: Int) -> Double {
        guard tokens > 0, maxTokens > 0 else {
            return zeroFraction
        }
        return min(1, max(0.04, Double(tokens) / Double(maxTokens)))
    }

    static func segments(inputTokens: Int, outputTokens: Int, capacity: Int) -> Segments {
        let inputTokens = max(0, inputTokens)
        let outputTokens = max(0, outputTokens)
        let totalTokens = inputTokens + outputTokens
        guard totalTokens > 0, capacity > 0 else {
            return Segments(inputFraction: zeroFraction, outputFraction: 0, totalFraction: zeroFraction)
        }

        let inputFraction = min(1, Double(inputTokens) / Double(capacity))
        let outputFraction = min(1 - inputFraction, Double(outputTokens) / Double(capacity))
        return Segments(
            inputFraction: inputFraction,
            outputFraction: outputFraction,
            totalFraction: min(1, inputFraction + outputFraction)
        )
    }
}

#Preview {
    MenuBarDashboardView(appState: AppState(), alertManager: AlertManager())
        .modelContainer(for: [UsageLedgerEntry.self, ProviderBalanceEntry.self], inMemory: true)
}
