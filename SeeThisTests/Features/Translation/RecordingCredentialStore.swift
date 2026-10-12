import Foundation
@testable import SeeThis

final class RecordingCredentialStore: CredentialStore, @unchecked Sendable {
    private var value: String?
    private(set) var lastWrittenCredential: String?
    private(set) var deleteCount = 0

    var currentCredential: String? {
        value
    }

    init(value: String?) {
        self.value = value
    }

    func setValue(_ value: String?) {
        self.value = value
    }

    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError> {
        .success(value)
    }

    func write(_ credential: String, for key: CredentialKey) -> Result<Void, CredentialStoreError> {
        lastWrittenCredential = credential
        value = credential
        return .success(())
    }

    func delete(_ key: CredentialKey) -> Result<Void, CredentialStoreError> {
        deleteCount += 1
        value = nil
        return .success(())
    }
}
