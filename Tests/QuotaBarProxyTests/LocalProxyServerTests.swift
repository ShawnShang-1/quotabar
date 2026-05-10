import Foundation
import XCTest
@testable import QuotaBarProxy

final class LocalProxyServerTests: XCTestCase {
    func testStartListensOnLocalhostAndHandlesAuthorizedRequest() async throws {
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
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: "local-secret"),
            provider: provider
        )

        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer local-secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"deepseek-chat","messages":[]}"#.utf8)

        let (body, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"ok":true}"#)
    }
}
