import Foundation
import QuotaBarCore
import XCTest
@testable import QuotaBarProxy

final class DeepSeekProviderTests: XCTestCase {
    func testBuildsOpenAICompatibleChatCompletionRequestWithDeepSeekAuthorization() throws {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/v1/chat/completions",
            headers: [
                "Authorization": "Bearer caller-token",
                "Content-Type": "application/json"
            ],
            body: Data(#"{"model":"deepseek-chat","messages":[{"role":"user","content":"hi"}]}"#.utf8)
        )

        let request = try provider.makeUpstreamRequest(for: incoming)

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, incoming.body)
    }

    func testBuildsAnthropicMessagesRequestWithDeepSeekAPIKeyHeader() throws {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/anthropic/v1/messages",
            headers: [
                "x-api-key": "local-token",
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json"
            ],
            body: Data(#"{"model":"deepseek-v4-pro[1m]","max_tokens":4,"messages":[{"role":"user","content":"hi"}]}"#.utf8)
        )

        let request = try provider.makeUpstreamRequest(for: incoming)

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "deepseek-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, incoming.body)
    }

    func testBuildsAnthropicMessagesRequestFromShortLocalPath() throws {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/anthropic/messages",
            headers: ["x-api-key": "local-token"],
            body: Data(#"{"model":"deepseek-v4-flash[1m]","messages":[]}"#.utf8)
        )

        let request = try provider.makeUpstreamRequest(for: incoming)

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
    }

    func testStreamingChatCompletionRequestsAskDeepSeekToIncludeUsage() throws {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/v1/chat/completions",
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"model":"deepseek-chat","stream":true,"messages":[{"role":"user","content":"hi"}]}"#.utf8)
        )

        let request = try provider.makeUpstreamRequest(for: incoming)

        let payload = try XCTUnwrap(request.httpBody.flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        let streamOptions = try XCTUnwrap(payload["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
    }

    func testStreamingChatCompletionPreservesExistingStreamOptions() throws {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/v1/chat/completions",
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"model":"deepseek-chat","stream":true,"stream_options":{"existing":true},"messages":[]}"#.utf8)
        )

        let request = try provider.makeUpstreamRequest(for: incoming)

        let payload = try XCTUnwrap(request.httpBody.flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        let streamOptions = try XCTUnwrap(payload["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
        XCTAssertEqual(streamOptions["existing"] as? Bool, true)
    }

    func testRejectsUnsupportedPathsBeforeForwarding() {
        let provider = DeepSeekProvider(apiKey: "deepseek-key")
        let incoming = ProxyHTTPRequest(method: .post, path: "/v1/models", headers: [:], body: nil)

        XCTAssertThrowsError(try provider.makeUpstreamRequest(for: incoming)) { error in
            XCTAssertEqual(error as? DeepSeekProvider.Error, .unsupportedRoute)
        }
    }

    func testExtractsUsageFromNonStreamingChatCompletionResponse() throws {
        let body = Data(
            """
            {
              "id": "chatcmpl-1",
              "object": "chat.completion",
              "usage": {
                "prompt_tokens": 12,
                "completion_tokens": 7,
                "total_tokens": 19,
                "prompt_cache_hit_tokens": 4,
                "prompt_cache_miss_tokens": 8
              }
            }
            """.utf8
        )

        let usage = try DeepSeekProvider.extractUsage(fromNonStreamingBody: body)

        XCTAssertEqual(
            usage,
            TokenUsage(
                inputTokens: 12,
                outputTokens: 7,
                cacheHitInputTokens: 4,
                cacheMissInputTokens: 8
            )
        )
    }

    func testExtractsUsageFromStreamingSSEFinalUsageChunk() throws {
        let body = Data(
            """
            data: {"id":"1","choices":[{"delta":{"content":"hi"}}],"usage":null}

            data: {"id":"1","choices":[],"usage":{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":8}}

            data: [DONE]

            """.utf8
        )

        let usage = try DeepSeekProvider.extractUsage(fromStreamingBody: body)

        XCTAssertEqual(
            usage,
            TokenUsage(
                inputTokens: 12,
                outputTokens: 7,
                cacheHitInputTokens: 4,
                cacheMissInputTokens: 8
            )
        )
    }

    func testExtractsUsageFromAnthropicMessagesResponse() throws {
        let body = Data(
            """
            {
              "id": "msg_1",
              "type": "message",
              "usage": {
                "input_tokens": 12,
                "output_tokens": 7,
                "cache_read_input_tokens": 4
              }
            }
            """.utf8
        )

        let usage = try DeepSeekProvider.extractUsage(fromAnthropicBody: body)

        XCTAssertEqual(
            usage,
            TokenUsage(
                inputTokens: 16,
                outputTokens: 7,
                cacheHitInputTokens: 4,
                cacheMissInputTokens: 12
            )
        )
    }

    func testExtractsUsageFromAnthropicStreamingEvents() throws {
        let body = Data(
            """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":4}}}

            event: message_delta
            data: {"type":"message_delta","usage":{"output_tokens":7}}

            event: message_stop
            data: {"type":"message_stop"}

            """.utf8
        )

        let usage = try DeepSeekProvider.extractUsage(fromAnthropicStreamingBody: body)

        XCTAssertEqual(
            usage,
            TokenUsage(
                inputTokens: 16,
                outputTokens: 7,
                cacheHitInputTokens: 4,
                cacheMissInputTokens: 12
            )
        )
    }

    func testForwardsStreamingResponsesWithoutParsingBody() async throws {
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-key")
                return UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/event-stream"],
                    body: Data("data: {\"delta\":\"hi\"}\n\n".utf8)
                )
            }
        )
        let incoming = ProxyHTTPRequest(
            method: .post,
            path: "/v1/chat/completions",
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"stream":true,"messages":[]}"#.utf8)
        )

        let response = try await provider.forward(incoming)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["Content-Type"], "text/event-stream")
        XCTAssertEqual(response.body, Data("data: {\"delta\":\"hi\"}\n\n".utf8))
    }
}
