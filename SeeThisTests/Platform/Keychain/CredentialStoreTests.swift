import Foundation
import Testing
@testable import SeeThis

struct CredentialStoreTests {
    @Test func storesReadsAndDeletesAKeychainCredential() throws {
        let client = FakeKeychainClient()
        let store = KeychainCredentialStore(client: client)
        let key = CredentialKey(service: "SeeThis.tests", account: "provider")
        let credential = "synthetic-\(UUID().uuidString)"

        #expect(try store.read(key).get() == nil)
        try store.write(credential, for: key).get()
        #expect(try store.read(key).get() == credential)
        try store.delete(key).get()
        #expect(try store.read(key).get() == nil)
    }

    @Test func rejectsAnEmptyCredentialBeforeWritingToKeychain() {
        let client = FakeKeychainClient()
        let store = KeychainCredentialStore(client: client)
        let key = CredentialKey(service: "SeeThis.tests", account: "provider")

        let result = store.write(" \n", for: key)

        guard case let .failure(error) = result else {
            Issue.record("Expected an empty credential to be rejected")
            return
        }
        #expect(error == .invalidCredential)
        #expect(client.writeCount == 0)
    }

    @Test func mapsInvalidStoredDataWithoutExposingItsContents() {
        let client = FakeKeychainClient(storedData: [0xFF, 0xFE])
        let store = KeychainCredentialStore(client: client)
        let key = CredentialKey(service: "SeeThis.tests", account: "provider")

        let result = store.read(key)

        #expect(result == .failure(.invalidCredential))
        #expect(String(describing: result).contains("FF") == false)
    }

    @Test func mapsKeychainFailuresWithoutIncludingTheCredential() {
        let client = FakeKeychainClient(readError: .status(-25299))
        let store = KeychainCredentialStore(client: client)
        let key = CredentialKey(service: "SeeThis.tests", account: "provider")

        let result = store.read(key)

        #expect(result == .failure(.keychainFailure(status: -25299)))
        #expect(String(describing: result).contains("synthetic") == false)
    }
}

private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    private(set) var writeCount = 0
    private var data: Data?
    private let readError: KeychainClientError?

    init(
        storedData: [UInt8]? = nil,
        readError: KeychainClientError? = nil
    ) {
        data = storedData.map { Data($0) }
        self.readError = readError
    }

    func read(service: String, account: String) -> Result<Data?, KeychainClientError> {
        if let readError { return .failure(readError) }
        return .success(data)
    }

    func write(_ data: Data, service: String, account: String) -> Result<Void, KeychainClientError> {
        writeCount += 1
        self.data = data
        return .success(())
    }

    func delete(service: String, account: String) -> Result<Void, KeychainClientError> {
        data = nil
        return .success(())
    }
}
