import Foundation
import Testing
@testable import SeeThis

struct ActionPermissionGrantStoreTests {
    @Test func grantsAreEmptyByDefaultAndPersistPerAction() {
        let suiteName = "ActionPermissionGrantStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let permission = ActionPermission.network(
            host: "api-free.deepl.com",
            egress: ["selection", "sourceLanguage", "targetLanguage"]
        )

        let initial = ActionPermissionGrantStore(defaults: defaults)
        #expect(initial.permissions(for: "translate").isEmpty)

        initial.setPermissions([permission], for: "translate")

        let reloaded = ActionPermissionGrantStore(defaults: defaults)
        #expect(reloaded.permissions(for: "translate") == [permission])
        #expect(reloaded.permissions(for: "other-action").isEmpty)
    }

    @Test func clearingOneActionDoesNotReuseOrRemoveAnotherActionsGrants() {
        let suiteName = "ActionPermissionGrantStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let permission = ActionPermission.localDictionary
        let store = ActionPermissionGrantStore(defaults: defaults)

        store.setPermissions([permission], for: "define")
        store.setPermissions([permission], for: "translate")
        store.setPermissions([], for: "translate")

        #expect(store.permissions(for: "translate").isEmpty)
        #expect(store.permissions(for: "define") == [permission])
    }

    @Test func malformedStoredGrantsFailClosedToEmpty() {
        let suiteName = "ActionPermissionGrantStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: ActionPermissionGrantStore.storageKey)

        let store = ActionPermissionGrantStore(defaults: defaults)

        #expect(store.permissions(for: "translate").isEmpty)
    }
}
