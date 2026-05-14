import QuotaBarCore
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

                    Text(appState.settings.hasDeepSeekAPIKey ? "已配置" : "缺失")
                        .foregroundStyle(appState.settings.hasDeepSeekAPIKey ? Color.secondary : Color.red)
                }

                HStack {
                    Text("余额")
                    Spacer()
                    Text(appState.balanceSummary.shortBalanceText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button("刷新余额") {
                    Task {
                        await appState.refreshBalance()
                    }
                }
                .disabled(!appState.settings.hasDeepSeekAPIKey)
            }

            Section("本机代理") {
                TextField("端口", value: $appState.settings.proxyPort, format: .number)

                TextField("本机 Bearer token", text: $appState.settings.proxyBearerToken)
                    .textSelection(.enabled)

                Toggle("QuotaBar 打开时自动启动代理", isOn: $appState.settings.autoStartProxy)

                HStack {
                    Text("Base URL")
                    Spacer()
                    Text(appState.proxyBaseURLText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                if appState.proxyStatus == .needsRestart {
                    Text("端口、token 或价格已变更，重启代理后生效。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("复制 URL") {
                        appState.copyProxyBaseURLToPasteboard()
                    }

                    Button("复制 Token") {
                        appState.copyProxyBearerTokenToPasteboard()
                    }
                }

                HStack {
                    Button("启动代理") {
                        Task {
                            await appState.startProxy()
                        }
                    }
                    .disabled(!appState.settings.hasDeepSeekAPIKey)

                    Button("重启") {
                        Task {
                            await appState.restartProxy()
                        }
                    }
                    .disabled(!appState.settings.hasDeepSeekAPIKey)

                    Button("停止代理") {
                        Task {
                            await appState.stopProxy()
                        }
                    }

                    Spacer()

                    Text(appState.proxyStatus.label)
                        .foregroundStyle(.secondary)
                }
            }

            Section("预算与提醒") {
                TextField(
                    "每日预算",
                    value: $appState.settings.dailyBudgetUSD,
                    format: .number.precision(.fractionLength(2))
                )

                TextField(
                    "低余额阈值",
                    value: $appState.settings.lowBalanceThreshold,
                    format: .number.precision(.fractionLength(2))
                )

                Slider(
                    value: $appState.settings.spikeMultiplier,
                    in: 1.25...5,
                    step: 0.25
                ) {
                    Text("突增倍数")
                } minimumValueLabel: {
                    Text("1.25x")
                } maximumValueLabel: {
                    Text("5x")
                }

                Toggle("用量通知", isOn: $appState.settings.notificationsEnabled)

                Stepper(
                    "每 \(appState.settings.refreshIntervalSeconds / 60) 分钟刷新",
                    value: $appState.settings.refreshIntervalSeconds,
                    in: 60...3600,
                    step: 60
                )

                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(notificationStateText)
                        .foregroundStyle(.secondary)
                }

                Button("请求通知权限") {
                    Task {
                        await alertManager.requestAuthorization()
                    }
                }
                .disabled(alertManager.authorizationState == .authorized)
            }

            Section("DeepSeek 价格（元 / 百万 tokens）") {
                pricingFields(
                    title: "V4 Flash",
                    pricing: $appState.settings.deepSeekPricing.v4Flash
                )
                pricingFields(
                    title: "V4 Pro",
                    pricing: $appState.settings.deepSeekPricing.v4Pro
                )
            }

            Section("账本") {
                Button("清空账本", role: .destructive) {
                    appState.clearLedger()
                }
            }

            Section("系统") {
                Toggle("登录时启动", isOn: $appState.settings.launchAtLogin)
            }

            if let message = appState.lastErrorMessage ?? alertManager.lastErrorMessage {
                Section("最近错误") {
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
            "未请求"
        case .denied:
            "已拒绝"
        case .authorized:
            "已允许"
        case .provisional:
            "临时允许"
        }
    }

    @ViewBuilder
    private func pricingFields(title: String, pricing: Binding<DeepSeekModelPricing>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField(
                "输入（缓存命中）",
                value: pricing.cacheHitInputUSDPerMillion,
                format: .number.precision(.fractionLength(3))
            )

            TextField(
                "输入（缓存未命中）",
                value: pricing.cacheMissInputUSDPerMillion,
                format: .number.precision(.fractionLength(3))
            )

            TextField(
                "输出",
                value: pricing.outputUSDPerMillion,
                format: .number.precision(.fractionLength(3))
            )
        }
    }
}

#Preview {
    SettingsView(appState: AppState(), alertManager: AlertManager())
        .modelContainer(for: [UsageLedgerEntry.self, ProviderBalanceEntry.self], inMemory: true)
}
