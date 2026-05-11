import Foundation

public struct ProxyAuthenticator: Sendable {
    public enum Result: Equatable, Sendable {
        case authorized
        case missingAuthorization
        case invalidAuthorizationScheme
        case invalidBearerToken
    }

    private let requiredBearerToken: String?

    public init(requiredBearerToken: String?) {
        self.requiredBearerToken = requiredBearerToken
    }

    public func authenticate(headers: [String: String]) -> Result {
        guard let requiredBearerToken, !requiredBearerToken.isEmpty else {
            return .authorized
        }

        let apiKeyMatches = headers.first(where: {
            $0.key.caseInsensitiveCompare("x-api-key") == .orderedSame
        })?.value == requiredBearerToken

        let authorization = headers.first(where: {
            $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
        })?.value

        if apiKeyMatches {
            return .authorized
        }

        guard let authorization else {
            return .missingAuthorization
        }

        let parts = authorization.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return .invalidAuthorizationScheme
        }

        return String(parts[1]) == requiredBearerToken ? .authorized : .invalidBearerToken
    }
}
