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
        guard incoming.path == "/v1/chat/completions" else {
            throw Error.unsupportedRoute
        }
        guard let url = URL(string: incoming.path, relativeTo: baseURL)?.absoluteURL else {
            throw Error.invalidUpstreamURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = incoming.method.rawValue
        request.httpBody = incoming.body
        copyForwardableHeaders(from: incoming, to: &request)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    public static func parseBalance(from body: Data) throws -> DeepSeekBalance {
        do {
            return try JSONDecoder().decode(DeepSeekBalance.self, from: body)
        } catch {
            throw Error.invalidBalancePayload
        }
    }

    private func copyForwardableHeaders(from incoming: ProxyHTTPRequest, to request: inout URLRequest) {
        let blockedHeaders = Set(["authorization", "host", "content-length", "connection"])
        for (name, value) in incoming.headers {
            guard !blockedHeaders.contains(name.lowercased()) else {
                continue
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
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
