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
        XCTAssertEqual(events[0].costUSD, Decimal(string: "0.000003192"))
        XCTAssertNil(events[0].clientLabel)
    }
}
