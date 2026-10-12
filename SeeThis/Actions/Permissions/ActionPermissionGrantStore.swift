import Foundation

nonisolated struct ActionPermissionGrantStore {
    static let storageKey = "actionPermissionGrants"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func permissions(for actionID: String) -> [ActionPermission] {
        guard let storedPermissions = readState().actions[actionID] else {
            return []
        }
        return storedPermissions.compactMap(ActionPermission.init(stored:))
    }

    func setPermissions(_ permissions: [ActionPermission], for actionID: String) {
        var state = readState()
        let uniquePermissions = permissions.reduce(into: [ActionPermission]()) { result, permission in
            guard !result.contains(permission) else { return }
            result.append(permission)
        }
        if uniquePermissions.isEmpty {
            state.actions.removeValue(forKey: actionID)
        } else {
            state.actions[actionID] = uniquePermissions.map(StoredPermission.init)
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func readState() -> StoredState {
        guard let data = defaults.data(forKey: Self.storageKey),
              let state = try? JSONDecoder().decode(StoredState.self, from: data),
              state.version == StoredState.currentVersion else {
            return StoredState()
        }
        return state
    }
}

nonisolated private struct StoredState: Codable {
    static let currentVersion = 1

    let version: Int
    var actions: [String: [StoredPermission]]

    init(version: Int = currentVersion, actions: [String: [StoredPermission]] = [:]) {
        self.version = version
        self.actions = actions
    }
}

nonisolated private struct StoredPermission: Codable {
    let kind: String
    let host: String?
    let egress: [String]?

    init(kind: String, host: String? = nil, egress: [String]? = nil) {
        self.kind = kind
        self.host = host
        self.egress = egress
    }

    init(_ permission: ActionPermission) {
        switch permission {
        case .localModel:
            self.init(kind: "localModel")
        case .localDictionary:
            self.init(kind: "localDictionary")
        case .authorizedDocument:
            self.init(kind: "authorizedDocument")
        case let .network(host, egress):
            self.init(kind: "network", host: host, egress: egress)
        }
    }
}

private extension ActionPermission {
    nonisolated init?(stored: StoredPermission) {
        switch stored.kind {
        case "localModel":
            self = .localModel
        case "localDictionary":
            self = .localDictionary
        case "authorizedDocument":
            self = .authorizedDocument
        case "network":
            guard let host = stored.host,
                  let egress = stored.egress,
                  !host.isEmpty,
                  !egress.isEmpty,
                  egress.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            self = .network(host: host, egress: egress)
        default:
            return nil
        }
    }
}
