import Foundation

public struct UsageLedgerQuery: Equatable, Sendable {
    public var models: Set<String>
    public var clientLabels: Set<String>
    public var statusCodes: Set<Int>
    public var interval: DateInterval?

    public init(
        models: Set<String> = [],
        clientLabels: Set<String> = [],
        statusCodes: Set<Int> = [],
        interval: DateInterval? = nil
    ) {
        self.models = models
        self.clientLabels = clientLabels
        self.statusCodes = statusCodes
        self.interval = interval
    }
}

public enum UsageLedgerExporter {
    public static func filter(_ events: [UsageEvent], query: UsageLedgerQuery) -> [UsageEvent] {
        events.filter { event in
            if !query.models.isEmpty, !query.models.contains(event.model) {
                return false
            }
            if !query.clientLabels.isEmpty, !query.clientLabels.contains(event.clientLabel ?? "") {
                return false
            }
            if !query.statusCodes.isEmpty, !query.statusCodes.contains(event.statusCode) {
                return false
            }
            if let interval = query.interval, !interval.contains(event.timestamp) {
                return false
            }
            return true
        }
    }

    public static func exportCSV(_ events: [UsageEvent]) throws -> String {
        let header = [
            "timestamp",
            "provider",
            "model",
            "input_tokens",
            "output_tokens",
            "cache_hit_input_tokens",
            "cache_miss_input_tokens",
            "total_tokens",
            "cost_usd",
            "status_code",
            "duration_ms",
            "client_label",
            "is_anomalous"
        ].joined(separator: ",")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows: [String] = events.map { event in
            return [
                formatter.string(from: event.timestamp),
                event.provider.rawValue,
                event.model,
                "\(event.usage.inputTokens)",
                "\(event.usage.outputTokens)",
                "\(event.usage.cacheHitInputTokens)",
                "\(event.usage.cacheMissInputTokens)",
                "\(event.usage.totalTokens)",
                event.costUSD.description,
                "\(event.statusCode)",
                "\(event.durationMS)",
                event.clientLabel ?? "",
                "\(event.isAnomalous)"
            ].map(csvEscape).joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func exportJSON(_ events: [UsageEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(events.map(UsageLedgerExportRecord.init(event:)))
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

public struct UsageLedgerExportRecord: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var provider: String
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheHitInputTokens: Int
    public var cacheMissInputTokens: Int
    public var totalTokens: Int
    public var costUSD: String
    public var statusCode: Int
    public var durationMS: Int
    public var clientLabel: String?
    public var isAnomalous: Bool

    public init(event: UsageEvent) {
        timestamp = event.timestamp
        provider = event.provider.rawValue
        model = event.model
        inputTokens = event.usage.inputTokens
        outputTokens = event.usage.outputTokens
        cacheHitInputTokens = event.usage.cacheHitInputTokens
        cacheMissInputTokens = event.usage.cacheMissInputTokens
        totalTokens = event.usage.totalTokens
        costUSD = event.costUSD.description
        statusCode = event.statusCode
        durationMS = event.durationMS
        clientLabel = event.clientLabel
        isAnomalous = event.isAnomalous
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case provider
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheHitInputTokens = "cache_hit_input_tokens"
        case cacheMissInputTokens = "cache_miss_input_tokens"
        case totalTokens = "total_tokens"
        case costUSD = "cost_usd"
        case statusCode = "status_code"
        case durationMS = "duration_ms"
        case clientLabel = "client_label"
        case isAnomalous = "is_anomalous"
    }
}
