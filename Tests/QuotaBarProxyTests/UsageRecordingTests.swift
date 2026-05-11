import Foundation
import QuotaBarCore
import XCTest
@testable import QuotaBarProxy

private actor UsageCapture {
    private(set) var events: [UsageEvent] = []

    func record(_ event: UsageEvent) {
        events.append(event)
    }
}

final class UsageRecordingTests: XCTestCase {
    func testHandleRecordsNonStreamingUsageMetadata() async throws {
        let capture = UsageCapture()
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { _ in
                UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(
                        """
                        {
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
                )
            }
        )
        let server = LocalProxyServer(
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: provider,
            usageRecorder: { event in
                await capture.record(event)
            }
        )

        let response = await server.handle(
            ProxyHTTPRequest(
                method: .post,
                path: "/v1/chat/completions",
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"model":"deepseek-chat","messages":[{"role":"user","content":"not stored"}]}"#.utf8)
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        let events = await capture.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "deepseek-chat")
        XCTAssertEqual(events[0].usage.inputTokens, 12)
        XCTAssertEqual(events[0].usage.outputTokens, 7)
        XCTAssertEqual(events[0].usage.cacheHitInputTokens, 4)
        XCTAssertEqual(events[0].usage.cacheMissInputTokens, 8)
        XCTAssertEqual(events[0].costUSD, Decimal(string: "0.0000030912"))
        XCTAssertNil(events[0].clientLabel)
    }

    func testHandleRecordsStreamingUsageMetadataFromSSEFinalChunk() async throws {
        let capture = UsageCapture()
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { _ in
                UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/event-stream"],
                    body: Data(
                        """
                        data: {"choices":[{"delta":{"content":"hi"}}],"usage":null}

                        data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":8}}

                        data: [DONE]

                        """.utf8
                    )
                )
            }
        )
        let server = LocalProxyServer(
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: provider,
            usageRecorder: { event in
                await capture.record(event)
            }
        )

        let response = await server.handle(
            ProxyHTTPRequest(
                method: .post,
                path: "/v1/chat/completions",
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"model":"deepseek-chat","stream":true,"messages":[{"role":"user","content":"not stored"}]}"#.utf8)
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        let events = await capture.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "deepseek-chat")
        XCTAssertEqual(events[0].usage.totalTokens, 19)
        XCTAssertEqual(events[0].costUSD, Decimal(string: "0.0000030912"))
    }

    func testHandleRecordsAnthropicMessagesUsageMetadata() async throws {
        let capture = UsageCapture()
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { request in
                XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "deepseek-key")
                return UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(
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
                )
            }
        )
        let server = LocalProxyServer(
            authenticator: ProxyAuthenticator(requiredBearerToken: "local-secret"),
            provider: provider,
            usageRecorder: { event in
                await capture.record(event)
            }
        )

        let response = await server.handle(
            ProxyHTTPRequest(
                method: .post,
                path: "/anthropic/v1/messages",
                headers: [
                    "x-api-key": "local-secret",
                    "Content-Type": "application/json",
                    "X-QuotaBar-Client": "cc-switch"
                ],
                body: Data(#"{"model":"deepseek-v4-pro[1m]","max_tokens":4,"messages":[{"role":"user","content":"not stored"}]}"#.utf8)
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        let events = await capture.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "deepseek-v4-pro[1m]")
        XCTAssertEqual(events[0].usage.inputTokens, 12)
        XCTAssertEqual(events[0].usage.outputTokens, 7)
        XCTAssertEqual(events[0].usage.cacheHitInputTokens, 4)
        XCTAssertEqual(events[0].usage.cacheMissInputTokens, 8)
        XCTAssertEqual(events[0].costUSD, Decimal(string: "0.0000095845"))
        XCTAssertEqual(events[0].clientLabel, "cc-switch")
    }
}
