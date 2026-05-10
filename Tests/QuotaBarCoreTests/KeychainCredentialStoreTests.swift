import XCTest
@testable import QuotaBarCore

final class KeychainCredentialStoreTests: XCTestCase {
    private let service = "com.quotabar.tests.\(UUID().uuidString)"
    private let account = "deepseek-api-key"

    override func tearDownWithError() throws {
        try? KeychainCredentialStore(service: service).delete(account: account)
        try super.tearDownWithError()
    }

    func testSavesLoadsAndDeletesSecret() throws {
        let store = KeychainCredentialStore(service: service)

        try store.save("sk-test-value", account: account)

        XCTAssertEqual(try store.load(account: account), "sk-test-value")

        try store.delete(account: account)
        XCTAssertNil(try store.load(account: account))
    }

    func testUpdatingExistingSecretReplacesValue() throws {
        let store = KeychainCredentialStore(service: service)

        try store.save("first", account: account)
        try store.save("second", account: account)

        XCTAssertEqual(try store.load(account: account), "second")
    }
}
