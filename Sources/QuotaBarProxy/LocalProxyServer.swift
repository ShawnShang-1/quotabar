import Foundation
import Darwin
import QuotaBarCore

public actor LocalProxyServer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case nonLocalhostBinding(String)
        case invalidPort(Int)
        case portInUse(Int)
        case requestBodyTooLarge(Int)
        case socketFailure(String)
    }

    public struct Configuration: Equatable, Sendable {
        public var host: String
        public var port: Int
        public var maxBodyBytes: Int

        public init(host: String = "127.0.0.1", port: Int = 0, maxBodyBytes: Int = 10 * 1_024 * 1_024) {
            self.host = host
            self.port = port
            self.maxBodyBytes = maxBodyBytes
        }

        public var isLocalhostBinding: Bool {
            host == "127.0.0.1" || host == "::1" || host.caseInsensitiveCompare("localhost") == .orderedSame
        }
    }

    private let configuration: Configuration
    private let authenticator: ProxyAuthenticator
    private let provider: DeepSeekProvider
    private let usageRecorder: (@Sendable (UsageEvent) async -> Void)?
    private var listenerFileDescriptor: CInt = -1
    private var listenerSource: DispatchSourceRead?

    public init(
        configuration: Configuration = Configuration(),
        authenticator: ProxyAuthenticator,
        provider: DeepSeekProvider,
        usageRecorder: (@Sendable (UsageEvent) async -> Void)? = nil
    ) {
        self.configuration = configuration
        self.authenticator = authenticator
        self.provider = provider
        self.usageRecorder = usageRecorder
    }

    public func handle(_ request: ProxyHTTPRequest) async -> ProxyHTTPResponse {
        let startedAt = Date()
        switch authenticator.authenticate(headers: request.headers) {
        case .authorized:
            break
        case .missingAuthorization, .invalidAuthorizationScheme, .invalidBearerToken:
            return ProxyHTTPResponse(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"unauthorized"}"#.utf8)
            )
        }
        if let body = request.body, body.count > configuration.maxBodyBytes {
            return ProxyHTTPResponse(
                statusCode: 413,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"request_body_too_large"}"#.utf8)
            )
        }

        do {
            let response = try await provider.forward(request)
            await recordUsageIfPresent(
                request: request,
                response: response,
                startedAt: startedAt
            )
            return response
        } catch DeepSeekProvider.Error.unsupportedRoute, DeepSeekProvider.Error.unsupportedMethod {
            return ProxyHTTPResponse(
                statusCode: 404,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"unsupported_route"}"#.utf8)
            )
        } catch {
            return ProxyHTTPResponse(
                statusCode: 502,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"upstream_failure"}"#.utf8)
            )
        }
    }

    private func recordUsageIfPresent(
        request: ProxyHTTPRequest,
        response: ProxyHTTPResponse,
        startedAt: Date
    ) async {
        guard
            let usageRecorder,
            let body = response.body,
            let usage = try? DeepSeekProvider.extractUsage(fromNonStreamingBody: body),
            let model = Self.extractModel(from: request.body)
        else {
            return
        }

        let cost = (try? DeepSeekPricing.current.estimateCostUSD(model: model, usage: usage)) ?? .zero
        let durationMS = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        let event = UsageEvent(
            timestamp: startedAt,
            provider: .deepSeek,
            model: model,
            usage: usage,
            costUSD: cost,
            statusCode: response.statusCode,
            durationMS: durationMS,
            clientLabel: request.headerValue(for: "X-QuotaBar-Client"),
            isAnomalous: response.statusCode >= 400
        )

        await usageRecorder(event)
    }

    private nonisolated static func extractModel(from body: Data?) -> String? {
        guard let body else {
            return nil
        }

        struct ChatRequest: Decodable {
            let model: String
        }

        return try? JSONDecoder().decode(ChatRequest.self, from: body).model
    }

    @discardableResult
    public func start() async throws -> Int {
        guard configuration.isLocalhostBinding else {
            throw Error.nonLocalhostBinding(configuration.host)
        }
        guard configuration.port >= 0, configuration.port <= 65_535 else {
            throw Error.invalidPort(configuration.port)
        }
        if listenerFileDescriptor >= 0 {
            return try boundPort(for: listenerFileDescriptor)
        }

        let fileDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw Error.socketFailure(String(cString: strerror(errno)))
        }
        let flags = fcntl(fileDescriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw Error.socketFailure(message)
        }

        var reuse = 1
        guard setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw Error.socketFailure(message)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(configuration.port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(ipv4LoopbackAddress))

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            if errno == EADDRINUSE {
                Darwin.close(fileDescriptor)
                throw Error.portInUse(configuration.port)
            }
            let message = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw Error.socketFailure(message)
        }

        guard Darwin.listen(fileDescriptor, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw Error.socketFailure(message)
        }

        listenerFileDescriptor = fileDescriptor

        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: DispatchQueue(label: "QuotaBar.LocalProxyServer.accept"))
        let maxBodyBytes = configuration.maxBodyBytes
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Self.acceptPendingConnections(on: fileDescriptor, server: self, maxBodyBytes: maxBodyBytes)
        }
        listenerSource = source
        source.resume()

        return try boundPort(for: fileDescriptor)
    }

    public func stop() {
        let fileDescriptor = listenerFileDescriptor
        listenerSource?.cancel()
        listenerSource = nil
        listenerFileDescriptor = -1
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
    }

    private var ipv4LoopbackAddress: String {
        configuration.host == "localhost" ? "127.0.0.1" : configuration.host
    }

    private func boundPort(for fileDescriptor: CInt) throws -> Int {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fileDescriptor, $0, &length)
            }
        }
        guard status == 0 else {
            throw Error.socketFailure(String(cString: strerror(errno)))
        }

        return Int(UInt16(bigEndian: address.sin_port))
    }

    private nonisolated static func acceptPendingConnections(
        on listenerFileDescriptor: CInt,
        server: LocalProxyServer,
        maxBodyBytes: Int
    ) {
        while true {
            let clientFileDescriptor = Darwin.accept(listenerFileDescriptor, nil, nil)
            if clientFileDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                return
            }
            let flags = fcntl(clientFileDescriptor, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(clientFileDescriptor, F_SETFL, flags & ~O_NONBLOCK)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                processConnection(clientFileDescriptor, server: server, maxBodyBytes: maxBodyBytes)
            }
        }
    }

    private nonisolated static func processConnection(
        _ fileDescriptor: CInt,
        server: LocalProxyServer,
        maxBodyBytes: Int
    ) {
        do {
            let request = try readHTTPRequest(from: fileDescriptor, maxBodyBytes: maxBodyBytes)
            Task.detached {
                let proxyResponse = await server.handle(request)
                try? writeHTTPResponse(proxyResponse, to: fileDescriptor)
                Darwin.close(fileDescriptor)
            }
        } catch Error.requestBodyTooLarge {
            let response = ProxyHTTPResponse(
                statusCode: 413,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"request_body_too_large"}"#.utf8)
            )
            try? writeHTTPResponse(response, to: fileDescriptor)
            Darwin.close(fileDescriptor)
        } catch {
            let response = ProxyHTTPResponse(
                statusCode: 400,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"bad_request"}"#.utf8)
            )
            try? writeHTTPResponse(response, to: fileDescriptor)
            Darwin.close(fileDescriptor)
        }
    }

    private nonisolated static func readHTTPRequest(from fileDescriptor: CInt, maxBodyBytes: Int) throws -> ProxyHTTPRequest {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)

        while !buffer.contains(Data("\r\n\r\n".utf8)) {
            let count = Darwin.recv(fileDescriptor, &chunk, chunk.count, 0)
            guard count > 0 else {
                throw Error.socketFailure("Client closed connection before headers were complete")
            }
            buffer.append(chunk, count: count)
            guard buffer.count <= 10 * 1_024 * 1_024 else {
                throw Error.socketFailure("Request headers exceeded limit")
            }
        }

        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            throw Error.socketFailure("Missing header terminator")
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw Error.socketFailure("Headers are not UTF-8")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw Error.socketFailure("Missing request line")
        }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2, let method = HTTPMethod(rawValue: requestParts[0]) else {
            throw Error.socketFailure("Unsupported HTTP method")
        }

        let path = requestParts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestParts[1]
        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = headers.first {
            $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame
        }.flatMap { Int($0.value) } ?? 0
        guard contentLength <= maxBodyBytes else {
            throw Error.requestBodyTooLarge(contentLength)
        }

        var body = Data(buffer[headerRange.upperBound...])
        guard body.count <= maxBodyBytes else {
            throw Error.requestBodyTooLarge(body.count)
        }
        while body.count < contentLength {
            let count = Darwin.recv(fileDescriptor, &chunk, min(chunk.count, contentLength - body.count), 0)
            guard count > 0 else {
                throw Error.socketFailure("Client closed connection before body was complete")
            }
            body.append(chunk, count: count)
            guard body.count <= maxBodyBytes else {
                throw Error.requestBodyTooLarge(body.count)
            }
        }

        if body.count > contentLength {
            body = body.prefix(contentLength)
        }

        return ProxyHTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: contentLength > 0 ? body : nil
        )
    }

    private nonisolated static func writeHTTPResponse(_ response: ProxyHTTPResponse, to fileDescriptor: CInt) throws {
        let body = response.body ?? Data()
        var headers = response.headers
        headers["Content-Length"] = "\(body.count)"
        headers["Connection"] = "close"

        let reason = statusReasonPhrase(for: response.statusCode)
        var headerString = "HTTP/1.1 \(response.statusCode) \(reason)\r\n"
        for (name, value) in headers {
            headerString += "\(name): \(value)\r\n"
        }
        headerString += "\r\n"

        var data = Data(headerString.utf8)
        data.append(body)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(fileDescriptor, baseAddress.advanced(by: sent), rawBuffer.count - sent, 0)
                guard count >= 0 else {
                    throw Error.socketFailure(String(cString: strerror(errno)))
                }
                sent += count
            }
        }
    }

    private nonisolated static func statusReasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 413: "Content Too Large"
        case 502: "Bad Gateway"
        default: "HTTP"
        }
    }
}
