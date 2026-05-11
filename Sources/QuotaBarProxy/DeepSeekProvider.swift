import Foundation
import QuotaBarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DeepSeekProvider: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedMethod
        case unsupportedRoute
        case invalidUpstreamURL
        case invalidUsagePayload
        case invalidBalancePayload
        case missingBalancePayload
    }

    public typealias Transport = @Sendable (URLRequest) async throws -> UpstreamHTTPResponse

    private let apiKey: String
    private let baseURL: URL
    private let transport: Transport

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        transport: @escaping Transport = DeepSeekProvider.urlSessionTransport
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public func makeUpstreamRequest(for incoming: ProxyHTTPRequest) throws -> URLRequest {
        guard incoming.method == .post else {
            throw Error.unsupportedMethod
        }
        guard let route = Route(path: incoming.path) else {
            throw Error.unsupportedRoute
        }
        guard let url = URL(string: route.upstreamPath, relativeTo: baseURL)?.absoluteURL else {
            throw Error.invalidUpstreamURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = incoming.method.rawValue
        request.httpBody = route == .openAIChatCompletions ? Self.bodyRequestingUsageWhenStreaming(incoming.body) : incoming.body
        copyForwardableHeaders(from: incoming, to: &request)
        switch route {
        case .openAIChatCompletions:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        return request
    }

    public func forward(_ incoming: ProxyHTTPRequest) async throws -> ProxyHTTPResponse {
        let request = try makeUpstreamRequest(for: incoming)
        let upstream = try await transport(request)

        return ProxyHTTPResponse(
            statusCode: upstream.statusCode,
            headers: upstream.headers,
            body: upstream.body
        )
    }

    public func fetchBalance() async throws -> DeepSeekBalance {
        guard let url = URL(string: "/user/balance", relativeTo: baseURL)?.absoluteURL else {
            throw Error.invalidUpstreamURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let response = try await transport(request)
        guard let body = response.body else {
            throw Error.missingBalancePayload
        }

        return try Self.parseBalance(from: body)
    }

    public static func extractUsage(fromNonStreamingBody body: Data) throws -> TokenUsage? {
        struct UpstreamUsage: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
            let promptCacheHitTokens: Int?
            let promptCacheMissTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
                case promptCacheHitTokens = "prompt_cache_hit_tokens"
                case promptCacheMissTokens = "prompt_cache_miss_tokens"
            }
        }

        struct ChatCompletionEnvelope: Decodable {
            let usage: UpstreamUsage?
        }

        do {
            guard let usage = try JSONDecoder().decode(ChatCompletionEnvelope.self, from: body).usage else {
                return nil
            }
            return TokenUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens,
                cacheHitInputTokens: usage.promptCacheHitTokens,
                cacheMissInputTokens: usage.promptCacheMissTokens
            )
        } catch {
            throw Error.invalidUsagePayload
        }
    }

    public static func extractUsage(fromStreamingBody body: Data) throws -> TokenUsage? {
        guard let text = String(data: body, encoding: .utf8) else {
            throw Error.invalidUsagePayload
        }

        var latestUsage: TokenUsage?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else {
                continue
            }

            let payload = line
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let payloadData = payload.data(using: .utf8) else {
                continue
            }

            if let usage = try? extractUsage(fromNonStreamingBody: payloadData) {
                latestUsage = usage
            }
        }

        return latestUsage
    }

    public static func extractUsage(fromAnthropicBody body: Data) throws -> TokenUsage? {
        do {
            return try JSONDecoder().decode(AnthropicUsageEnvelope.self, from: body).usage?.tokenUsage
        } catch {
            throw Error.invalidUsagePayload
        }
    }

    public static func extractUsage(fromAnthropicStreamingBody body: Data) throws -> TokenUsage? {
        guard let text = String(data: body, encoding: .utf8) else {
            throw Error.invalidUsagePayload
        }

        var aggregate = AnthropicUsage()
        var hasUsage = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else {
                continue
            }

            let payload = line
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payloadData = payload.data(using: .utf8) else {
                continue
            }

            if let envelope = try? JSONDecoder().decode(AnthropicUsageEnvelope.self, from: payloadData),
               let usage = envelope.usage,
               usage.hasKnownTokenField {
                aggregate.merge(usage)
                hasUsage = true
                continue
            }

            if let envelope = try? JSONDecoder().decode(AnthropicMessageStartEnvelope.self, from: payloadData),
               let usage = envelope.message.usage,
               usage.hasKnownTokenField {
                aggregate.merge(usage)
                hasUsage = true
            }
        }

        return hasUsage ? aggregate.tokenUsage : nil
    }

    public static func parseBalance(from body: Data) throws -> DeepSeekBalance {
        do {
            return try JSONDecoder().decode(DeepSeekBalance.self, from: body)
        } catch {
            throw Error.invalidBalancePayload
        }
    }

    private func copyForwardableHeaders(from incoming: ProxyHTTPRequest, to request: inout URLRequest) {
        let blockedHeaders = Set(["authorization", "x-api-key", "host", "content-length", "connection"])
        for (name, value) in incoming.headers {
            guard !blockedHeaders.contains(name.lowercased()) else {
                continue
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func bodyRequestingUsageWhenStreaming(_ body: Data?) -> Data? {
        guard
            let body,
            var payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            payload["stream"] as? Bool == true
        else {
            return body
        }

        var streamOptions = payload["stream_options"] as? [String: Any] ?? [:]
        streamOptions["include_usage"] = true
        payload["stream_options"] = streamOptions

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? body
    }

    public static func urlSessionTransport(_ request: URLRequest) async throws -> UpstreamHTTPResponse {
        let (body, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        return UpstreamHTTPResponse(
            statusCode: httpResponse?.statusCode ?? 0,
            headers: httpResponse?.allHeaderFields.reduce(into: [String: String]()) { partial, header in
                if let key = header.key as? String {
                    partial[key] = String(describing: header.value)
                }
            } ?? [:],
            body: body
        )
    }
}

private enum Route: Equatable {
    case openAIChatCompletions
    case anthropicMessages

    init?(path: String) {
        switch path {
        case "/v1/chat/completions":
            self = .openAIChatCompletions
        case "/anthropic/v1/messages", "/anthropic/messages":
            self = .anthropicMessages
        default:
            return nil
        }
    }

    var upstreamPath: String {
        switch self {
        case .openAIChatCompletions:
            "/v1/chat/completions"
        case .anthropicMessages:
            "/anthropic/v1/messages"
        }
    }
}

private struct AnthropicUsageEnvelope: Decodable {
    var usage: AnthropicUsage?
}

private struct AnthropicMessageStartEnvelope: Decodable {
    var message: Message

    struct Message: Decodable {
        var usage: AnthropicUsage?
    }
}

private struct AnthropicUsage: Decodable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadInputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    init(inputTokens: Int? = nil, outputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    mutating func merge(_ usage: AnthropicUsage) {
        if let inputTokens = usage.inputTokens {
            self.inputTokens = max(self.inputTokens ?? 0, inputTokens)
        }
        if let outputTokens = usage.outputTokens {
            self.outputTokens = max(self.outputTokens ?? 0, outputTokens)
        }
        if let cacheReadInputTokens = usage.cacheReadInputTokens {
            self.cacheReadInputTokens = max(self.cacheReadInputTokens ?? 0, cacheReadInputTokens)
        }
    }

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cacheHitInputTokens: cacheReadInputTokens ?? 0
        )
    }

    var hasKnownTokenField: Bool {
        inputTokens != nil || outputTokens != nil || cacheReadInputTokens != nil
    }
}

extension DeepSeekProvider: ProviderAdapter {
    public var provider: ProviderKind {
        .deepSeek
    }

    public var capabilities: Set<ProviderCapability> {
        [.balance, .tokenPricing, .usageLedger]
    }

    public func fetchBalanceSnapshot() async throws -> ProviderBalanceSnapshot {
        let balance = try await fetchBalance()
        return ProviderBalanceSnapshot(
            provider: .deepSeek,
            currency: balance.primaryCurrency ?? "CNY",
            totalBalance: balance.primaryTotalBalance ?? .zero,
            isAvailable: balance.isAvailable,
            updatedAt: .now
        )
    }
}
