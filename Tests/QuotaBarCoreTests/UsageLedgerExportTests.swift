import Foundation
import Testing
@testable import QuotaBarCore

@Test func ledgerQueryFiltersByModelClientAndStatus() {
    let events = makeLedgerEvents()
    let query = UsageLedgerQuery(
        models: ["deepseek-chat"],
        clientLabels: ["codex"],
        statusCodes: [200]
    )

    let filtered = UsageLedgerExporter.filter(events, query: query)

    #expect(filtered.map(\.model) == ["deepseek-chat"])
    #expect(filtered.map(\.clientLabel) == ["codex"])
    #expect(filtered.map(\.statusCode) == [200])
}

@Test func csvExportContainsMetadataOnly() throws {
    let csv = try UsageLedgerExporter.exportCSV(makeLedgerEvents())

    #expect(csv.contains("timestamp,provider,model,input_tokens,output_tokens,cache_hit_input_tokens,cache_miss_input_tokens,total_tokens,cost_usd,status_code,duration_ms,client_label,is_anomalous"))
    #expect(csv.contains("deepseek-chat"))
    #expect(!csv.localizedCaseInsensitiveContains("prompt"))
    #expect(!csv.localizedCaseInsensitiveContains("response"))
}

@Test func jsonExportContainsMetadataOnly() throws {
    let data = try UsageLedgerExporter.exportJSON(makeLedgerEvents())
    let json = String(decoding: data, as: UTF8.self)

    #expect(json.contains("\"model\" : \"deepseek-chat\""))
    #expect(!json.localizedCaseInsensitiveContains("prompt"))
    #expect(!json.localizedCaseInsensitiveContains("response"))
}

private func makeLedgerEvents() -> [UsageEvent] {
    [
        UsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            provider: .deepSeek,
            model: "deepseek-chat",
            usage: TokenUsage(inputTokens: 12, outputTokens: 7, cacheHitInputTokens: 4, cacheMissInputTokens: 8),
            costUSD: Decimal(string: "0.0000030912")!,
            statusCode: 200,
            durationMS: 120,
            clientLabel: "codex",
            isAnomalous: false
        ),
        UsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_800_000_060),
            provider: .deepSeek,
            model: "deepseek-reasoner",
            usage: TokenUsage(inputTokens: 30, outputTokens: 15),
            costUSD: Decimal(string: "0.000012")!,
            statusCode: 429,
            durationMS: 980,
            clientLabel: "editor",
            isAnomalous: true
        )
    ]
}
