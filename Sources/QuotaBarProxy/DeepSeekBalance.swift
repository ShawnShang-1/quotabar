import Foundation

public struct DeepSeekBalance: Codable, Equatable, Sendable {
    public var isAvailable: Bool
    public var balanceInfos: [DeepSeekBalanceInfo]

    public init(isAvailable: Bool, balanceInfos: [DeepSeekBalanceInfo]) {
        self.isAvailable = isAvailable
        self.balanceInfos = balanceInfos
    }

    public var primaryCurrency: String? {
        balanceInfos.first?.currency
    }

    public var primaryTotalBalance: Decimal? {
        balanceInfos.first?.totalBalance
    }

    private enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

public struct DeepSeekBalanceInfo: Codable, Equatable, Sendable {
    public var currency: String
    public var totalBalance: Decimal
    public var grantedBalance: Decimal
    public var toppedUpBalance: Decimal

    public init(
        currency: String,
        totalBalance: Decimal,
        grantedBalance: Decimal,
        toppedUpBalance: Decimal
    ) {
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }

    private enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = try container.decode(String.self, forKey: .currency)
        totalBalance = try container.decodeDecimal(forKey: .totalBalance)
        grantedBalance = try container.decodeDecimal(forKey: .grantedBalance)
        toppedUpBalance = try container.decodeDecimal(forKey: .toppedUpBalance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currency, forKey: .currency)
        try container.encode(totalBalance.description, forKey: .totalBalance)
        try container.encode(grantedBalance.description, forKey: .grantedBalance)
        try container.encode(toppedUpBalance.description, forKey: .toppedUpBalance)
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        if let string = try? decode(String.self, forKey: key), let decimal = Decimal(string: string) {
            return decimal
        }
        if let double = try? decode(Double.self, forKey: key) {
            return Decimal(double)
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected decimal string or number")
    }
}
