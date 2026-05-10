import Foundation
import XCTest
@testable import QuotaBarProxy

final class DeepSeekBalanceTests: XCTestCase {
    func testParsesDeepSeekBalanceResponse() throws {
        let body = Data(
            """
            {
              "is_available": true,
              "balance_infos": [
                {
                  "currency": "CNY",
                  "total_balance": "110.93",
                  "granted_balance": "0.00",
                  "topped_up_balance": "110.93"
                }
              ]
            }
            """.utf8
        )

        let balance = try DeepSeekProvider.parseBalance(from: body)

        XCTAssertTrue(balance.isAvailable)
        XCTAssertEqual(balance.primaryCurrency, "CNY")
        XCTAssertEqual(balance.primaryTotalBalance, Decimal(string: "110.93"))
    }

    func testFetchBalanceBuildsDeepSeekBalanceRequest() async throws {
        let provider = DeepSeekProvider(
            apiKey: "deepseek-key",
            transport: { request in
                XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-key")

                return UpstreamHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(#"{"is_available":true,"balance_infos":[]}"#.utf8)
                )
            }
        )

        let balance = try await provider.fetchBalance()

        XCTAssertTrue(balance.isAvailable)
    }
}
