import Foundation
import XCTest
@testable import QuotaBarProxy

final class LocalProxyReliabilityTests: XCTestCase {
    func testStartIsIdempotentAndStopIsIdempotent() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(apiKey: "deepseek-key")
        )

        let firstPort = try await server.start()
        let secondPort = try await server.start()
        await server.stop()
        await server.stop()

        XCTAssertEqual(firstPort, secondPort)
    }

    func testPortInUseReportsDedicatedError() async throws {
        let first = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(apiKey: "deepseek-key")
        )
        let port = try await first.start()
        defer {
            Task {
                await first.stop()
            }
        }

        let second = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: port),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(apiKey: "deepseek-key")
        )

        do {
            _ = try await second.start()
            XCTFail("Expected port in use")
        } catch {
            XCTAssertEqual(error as? LocalProxyServer.Error, .portInUse(port))
        }
    }

    func testRejectsOversizedRequestBodyBeforeForwarding() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0, maxBodyBytes: 8),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { _ in
                    XCTFail("Oversized requests should not reach upstream")
                    return UpstreamHTTPResponse(statusCode: 200)
                }
            )
        )

        let response = await server.handle(
            ProxyHTTPRequest(
                method: .post,
                path: "/v1/chat/completions",
                headers: [:],
                body: Data(repeating: 0, count: 9)
            )
        )

        XCTAssertEqual(response.statusCode, 413)
    }

    func testStopAfterHandlingConnectionAllowsImmediatePortReuse() async throws {
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { _ in
                UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(#"{"ok":true}"#.utf8)
                )
            }
        )
        let first = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: provider
        )
        let port = try await first.start()

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"model":"deepseek-chat","messages":[]}"#.utf8)
        _ = try await URLSession.shared.data(for: request)

        await first.stop()

        let second = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: port),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: provider
        )
        _ = try await second.start()
        await second.stop()
    }
}
