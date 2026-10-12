import Foundation
import Security

nonisolated struct CredentialKey: Hashable, Sendable {
    let service: String
    let account: String
}

nonisolated enum KeychainClientError: Error, Equatable, Sendable {
    case status(Int32)
}

nonisolated protocol KeychainClient: Sendable {
    func read(
        service: String,
        account: String
    ) -> Result<Data?, KeychainClientError>

    func write(
        _ data: Data,
        service: String,
        account: String
    ) -> Result<Void, KeychainClientError>

    func delete(
        service: String,
        account: String
    ) -> Result<Void, KeychainClientError>
}

nonisolated enum CredentialStoreError: Error, Equatable, Sendable {
    case invalidCredential
    case keychainFailure(status: Int32)
}

nonisolated protocol CredentialStore: Sendable {
    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError>
    func write(_ credential: String, for key: CredentialKey) -> Result<Void, CredentialStoreError>
    func delete(_ key: CredentialKey) -> Result<Void, CredentialStoreError>
}

nonisolated struct KeychainCredentialStore: CredentialStore, Sendable {
    private let client: any KeychainClient

    init(client: any KeychainClient = SystemKeychainClient()) {
        self.client = client
    }

    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError> {
        switch client.read(service: key.service, account: key.account) {
        case .success(nil):
            return .success(nil)
        case let .success(data?):
            guard let credential = String(data: data, encoding: .utf8),
                  !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.invalidCredential)
            }
            return .success(credential)
        case let .failure(error):
            return .failure(Self.map(error))
        }
    }

    func write(
        _ credential: String,
        for key: CredentialKey
    ) -> Result<Void, CredentialStoreError> {
        guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = credential.data(using: .utf8) else {
            return .failure(.invalidCredential)
        }

        switch client.write(data, service: key.service, account: key.account) {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(Self.map(error))
        }
    }

    func delete(_ key: CredentialKey) -> Result<Void, CredentialStoreError> {
        switch client.delete(service: key.service, account: key.account) {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(Self.map(error))
        }
    }

    private static func map(_ error: KeychainClientError) -> CredentialStoreError {
        switch error {
        case let .status(status):
            .keychainFailure(status: status)
        }
    }
}

private struct SystemKeychainClient: KeychainClient {
    func read(
        service: String,
        account: String
    ) -> Result<Data?, KeychainClientError> {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query(service: service, account: account, returningData: true),
            &item
        )
        switch status {
        case errSecSuccess:
            return .success(item as? Data)
        case errSecItemNotFound:
            return .success(nil)
        default:
            return .failure(.status(status))
        }
    }

    func write(
        _ data: Data,
        service: String,
        account: String
    ) -> Result<Void, KeychainClientError> {
        let itemQuery = query(service: service, account: account, returningData: false)
        let updateStatus = SecItemUpdate(
            itemQuery,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return .success(())
        case errSecItemNotFound:
            var attributes = baseAttributes(service: service, account: account)
            attributes[kSecValueData as String] = data
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            return addStatus == errSecSuccess
                ? .success(())
                : .failure(.status(addStatus))
        default:
            return .failure(.status(updateStatus))
        }
    }

    func delete(
        service: String,
        account: String
    ) -> Result<Void, KeychainClientError> {
        let status = SecItemDelete(query(service: service, account: account, returningData: false))
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return .success(())
        default:
            return .failure(.status(status))
        }
    }

    private func query(
        service: String,
        account: String,
        returningData: Bool
    ) -> CFDictionary {
        var query = baseAttributes(service: service, account: account)
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query as CFDictionary
    }

    private func baseAttributes(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
