import XCTest
@testable import QuotaBarProxy

final class ProxyAuthenticatorTests: XCTestCase {
    func testAllowsMatchingBearerToken() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: "local-secret")

        XCTAssertEqual(
            authenticator.authenticate(headers: ["Authorization": "Bearer local-secret"]),
            .authorized
        )
    }

    func testAllowsMatchingAnthropicAPIKeyHeader() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: "local-secret")

        XCTAssertEqual(
            authenticator.authenticate(headers: ["x-api-key": "local-secret"]),
            .authorized
        )
    }

    func testAllowsMatchingBearerTokenWhenIncorrectAPIKeyHeaderIsAlsoPresent() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: "local-secret")

        XCTAssertEqual(
            authenticator.authenticate(headers: [
                "x-api-key": "stale-secret",
                "Authorization": "Bearer local-secret"
            ]),
            .authorized
        )
    }

    func testRejectsMissingBearerTokenWhenRequired() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: "local-secret")

        XCTAssertEqual(authenticator.authenticate(headers: [:]), .missingAuthorization)
    }

    func testRejectsIncorrectBearerToken() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: "local-secret")

        XCTAssertEqual(
            authenticator.authenticate(headers: ["Authorization": "Bearer wrong-secret"]),
            .invalidBearerToken
        )
    }

    func testAllowsRequestsWhenNoCallerTokenIsConfigured() {
        let authenticator = ProxyAuthenticator(requiredBearerToken: nil)

        XCTAssertEqual(authenticator.authenticate(headers: [:]), .authorized)
    }

    func testLocalProxyConfigurationDefaultsToLocalhostBinding() {
        let configuration = LocalProxyServer.Configuration()

        XCTAssertTrue(configuration.isLocalhostBinding)
    }

    func testLocalProxyRejectsNonLocalhostBindingAtStartBoundary() async {
        let server = LocalProxyServer(
            configuration: LocalProxyServer.Configuration(host: "0.0.0.0", port: 8080),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(apiKey: "deepseek-key")
        )

        do {
            try await server.start()
            XCTFail("Expected start to reject non-localhost binding")
        } catch {
            XCTAssertEqual(error as? LocalProxyServer.Error, .nonLocalhostBinding("0.0.0.0"))
        }
    }
}
