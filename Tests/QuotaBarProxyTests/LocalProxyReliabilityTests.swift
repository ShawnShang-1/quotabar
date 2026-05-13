import Foundation
import Darwin
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

    func testRejectsOversizedRequestHeadersBeforeForwarding() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0, maxHeaderBytes: 128),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { _ in
                    XCTFail("Oversized headers should not reach upstream")
                    return UpstreamHTTPResponse(statusCode: 200)
                }
            )
        )
        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        let response = try sendRawHTTPRequest(
            """
            POST /v1/chat/completions HTTP/1.1\r
            Host: 127.0.0.1\r
            X-Fill: \(String(repeating: "a", count: 256))\r
            Content-Length: 0\r
            \r

            """,
            port: port
        )

        XCTAssertTrue(response.contains("431 Request Header Fields Too Large"))
        XCTAssertTrue(response.contains("request_headers_too_large"))
    }

    func testAcceptsLargeRequestBodyWhenHeadersStayUnderLimit() async throws {
        let body = String(repeating: "x", count: 256)
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0, maxHeaderBytes: 128),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { request in
                    XCTAssertEqual(request.httpBody?.count, body.utf8.count)
                    return UpstreamHTTPResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"],
                        body: Data(#"{"ok":true}"#.utf8)
                    )
                }
            )
        )
        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        let response = try sendRawHTTPRequest(
            """
            POST /v1/chat/completions HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: \(body.utf8.count)\r
            \r
            \(body)
            """,
            port: port
        )

        XCTAssertTrue(response.contains("200 OK"))
        XCTAssertTrue(response.hasSuffix(#"{"ok":true}"#))
    }

    func testRejectsNegativeContentLengthInsteadOfCrashing() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { _ in
                    XCTFail("Invalid content length should not reach upstream")
                    return UpstreamHTTPResponse(statusCode: 200)
                }
            )
        )
        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        let response = try sendRawHTTPRequest(
            """
            POST /v1/chat/completions HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: -1\r
            \r

            ignored
            """,
            port: port
        )

        XCTAssertTrue(response.contains("400 Bad Request"))
        XCTAssertTrue(response.contains("bad_request"))
    }

    func testRejectsChunkedRequestBodiesInsteadOfForwardingUnsupportedFraming() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { _ in
                    XCTFail("Chunked requests should not reach upstream")
                    return UpstreamHTTPResponse(statusCode: 200)
                }
            )
        )
        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        let response = try sendRawHTTPRequest(
            """
            POST /v1/chat/completions HTTP/1.1\r
            Host: 127.0.0.1\r
            Transfer-Encoding: chunked\r
            \r
            0\r
            \r

            """,
            port: port
        )

        XCTAssertTrue(response.contains("400 Bad Request"))
        XCTAssertTrue(response.contains("bad_request"))
    }

    func testDoesNotReturnHopByHopHeadersFromUpstream() async throws {
        let server = LocalProxyServer(
            configuration: .init(host: "127.0.0.1", port: 0),
            authenticator: ProxyAuthenticator(requiredBearerToken: nil),
            provider: DeepSeekProvider(
                apiKey: "deepseek-key",
                transport: { _ in
                    UpstreamHTTPResponse(
                        statusCode: 200,
                        headers: [
                            "connection": "keep-alive, X-Connection-Only",
                            "Transfer-Encoding": "chunked",
                            "Content-Length": "999",
                            "X-Connection-Only": "drop-me",
                            "X-QuotaBar-Test": "kept"
                        ],
                        body: Data("hello".utf8)
                    )
                }
            )
        )
        let port = try await server.start()
        defer {
            Task {
                await server.stop()
            }
        }

        let response = try sendRawHTTPRequest(
            """
            POST /v1/chat/completions HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: 0\r
            \r

            """,
            port: port
        )

        XCTAssertFalse(response.lowercased().contains("transfer-encoding:"))
        XCTAssertFalse(response.lowercased().contains("connection: keep-alive"))
        XCTAssertFalse(response.contains("X-Connection-Only: drop-me"))
        XCTAssertFalse(response.contains("Content-Length: 999"))
        XCTAssertTrue(response.contains("Content-Length: 5"))
        XCTAssertTrue(response.contains("X-QuotaBar-Test: kept"))
        XCTAssertTrue(response.hasSuffix("hello"))
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

    private func sendRawHTTPRequest(_ request: String, port: Int) throws -> String {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fileDescriptor, 0)
        defer {
            close(fileDescriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connectStatus, 0)

        let bytes = Array(request.utf8)
        let sent = bytes.withUnsafeBytes {
            send(fileDescriptor, $0.baseAddress, $0.count, 0)
        }
        XCTAssertEqual(sent, bytes.count)

        var buffer = [UInt8](repeating: 0, count: 4_096)
        let count = recv(fileDescriptor, &buffer, buffer.count, 0)
        XCTAssertGreaterThan(count, 0)
        return String(decoding: buffer.prefix(max(0, count)), as: UTF8.self)
    }
}
