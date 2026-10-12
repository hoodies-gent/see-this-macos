import Foundation
import Testing
@testable import SeeThis

struct TranslateSettingsStoreTests {
    @Test @MainActor func targetLanguageDefaultsToSystemLanguageAndPersistsNormalizedCode() {
        let fixture = isolatedDefaults()
        let defaults = fixture.defaults
        defer { defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: nil)
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )

        #expect(!store.targetLanguageCode.isEmpty)

        store.setTargetLanguage(" zh-hans ")

        let reloaded = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        #expect(store.targetLanguageCode == "ZH-HANS")
        #expect(reloaded.targetLanguageCode == "ZH-HANS")
    }

    @Test @MainActor func startsDisabledWhenCredentialOrGrantIsMissing() {
        let fixture = isolatedDefaults()
        let defaults = fixture.defaults
        defer { defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: nil)
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )

        #expect(store.hasCredential == false)
        #expect(store.isNetworkAuthorized == false)
        #expect(store.isConfigured == false)
    }

    @Test @MainActor func verifiedCredentialAndGrantEnableTranslateWithoutPersistingTheKey() async {
        let fixture = isolatedDefaults()
        let defaults = fixture.defaults
        defer { defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: nil)
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults,
            credentialValidator: FixedDeepLCredentialValidator(result: .success(()))
        )

        let saveResult = await store.saveCredential(" candidate ")
        guard case .success = saveResult else {
            Issue.record("Expected credential save to succeed.")
            return
        }
        store.setNetworkAuthorization(true)

        #expect(store.hasCredential)
        #expect(store.isNetworkAuthorized)
        #expect(store.isConfigured)
        #expect(credentialStore.lastWrittenCredential == "candidate")
        #expect(defaults.string(forKey: "deepl.api-key") == nil)
        #expect(defaults.data(forKey: ActionPermissionGrantStore.storageKey) != nil)
    }

    @Test(
        arguments: [
            DeepLCredentialValidationError.rejected,
            .timeout,
            .invalidResponse
        ]
    )
    @MainActor
    func failedValidationNeverWritesTheCandidate(
        validationError: DeepLCredentialValidationError
    ) async {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: nil)
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            credentialValidator: FixedDeepLCredentialValidator(
                result: .failure(validationError)
            )
        )

        let result = await store.saveCredential("candidate")

        guard case let .failure(error) = result else {
            Issue.record("Expected validation to stop the save.")
            return
        }
        #expect(error == .validation(validationError))
        #expect(credentialStore.lastWrittenCredential == nil)
        #expect(credentialStore.currentCredential == nil)
    }

    @Test @MainActor func rejectedReplacementPreservesTheWorkingKeyAndPermission() async {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: "old-key")
        let grantStore = ActionPermissionGrantStore(defaults: fixture.defaults)
        let lensStore = LensStore(defaults: fixture.defaults)
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: grantStore,
            defaults: fixture.defaults,
            lensStore: lensStore,
            credentialValidator: FixedDeepLCredentialValidator(result: .failure(.rejected))
        )
        store.setNetworkAuthorization(true)
        #expect(store.setDeepLLensVisible(true))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)

        let result = await store.saveCredential("invalid-candidate")

        guard case let .failure(error) = result else {
            Issue.record("Expected the replacement to be rejected.")
            return
        }
        #expect(error == .validation(.rejected))
        #expect(credentialStore.currentCredential == "old-key")
        #expect(credentialStore.lastWrittenCredential == nil)
        #expect(store.hasCredential)
        #expect(store.isNetworkAuthorized)
        #expect(lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID))
        #expect(lensStore.defaultLensID == TranslateSettingsStore.actionID)
    }

    @Test @MainActor func setupDoesNotAutomaticallyShowDeepLInTheOverlay() async {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let lensStore = LensStore(defaults: fixture.defaults)
        let store = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: nil),
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore,
            credentialValidator: FixedDeepLCredentialValidator(result: .success(()))
        )
        store.setNetworkAuthorization(true)

        guard case .success = await store.saveCredential("candidate") else {
            Issue.record("Expected setup to succeed.")
            return
        }

        #expect(store.isConfigured)
        #expect(!lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID))
    }

    @Test @MainActor func deepLVisibilityRequiresCompleteSetupAndSharedCapacity() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let lensStore = LensStore(defaults: fixture.defaults)
        let missingKey = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: nil),
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore
        )
        missingKey.setNetworkAuthorization(true)
        #expect(!missingKey.setDeepLLensVisible(true))

        let configured = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: "synthetic-key"),
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore
        )
        for index in 1...4 {
            let lens = lensStore.addCustomLens(
                displayName: "Capacity \(index)",
                preference: "Capacity prompt \(index)."
            )
            #expect(lensStore.setInlineLens(id: lens.id, isEnabled: true))
        }
        #expect(configured.isNetworkAuthorized)
        #expect(!configured.setDeepLLensVisible(true))
    }

    @Test @MainActor func deletingKeyOrRevokingGrantHidesDeepLAndClearsItsDefault() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let lensStore = LensStore(defaults: fixture.defaults)
        let credentialStore = RecordingCredentialStore(value: "synthetic-key")
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore
        )
        store.setNetworkAuthorization(true)
        #expect(store.setDeepLLensVisible(true))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)

        guard case .success = store.deleteCredential() else {
            Issue.record("Expected credential deletion to succeed.")
            return
        }
        #expect(!lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID))
        #expect(lensStore.defaultLensID == nil)

        credentialStore.setValue("replacement-key")
        store.refresh()
        store.setNetworkAuthorization(true)
        #expect(store.setDeepLLensVisible(true))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)

        store.setNetworkAuthorization(false)
        #expect(!lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID))
        #expect(lensStore.defaultLensID == nil)
    }

    @Test @MainActor func invalidatingOnlyVisibleDeepLLensRestoresALocalFallback() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let lensStore = LensStore(defaults: fixture.defaults)
        let store = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: "synthetic-key"),
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore
        )
        store.setNetworkAuthorization(true)
        #expect(store.setDeepLLensVisible(true))
        #expect(lensStore.setInlineLens(id: ExplanationLens.plain.id, isEnabled: false))
        #expect(lensStore.setInlineLens(id: ExplanationLens.localTranslateID, isEnabled: false))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)

        store.setNetworkAuthorization(false)

        #expect(lensStore.inlineLensIDs == [ExplanationLens.plain.id])
        #expect(lensStore.defaultLensID == nil)
    }

    @Test @MainActor func launchRemovesStoredDeepLVisibilityWhenSetupIsIncomplete() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let lensStore = LensStore(defaults: fixture.defaults)
        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)

        _ = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: nil),
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            lensStore: lensStore
        )

        #expect(!lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID))
        #expect(lensStore.defaultLensID == nil)
    }

    @Test @MainActor func concurrentSaveIsRejectedWithoutASecondValidationOrWrite() async {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: nil)
        let validator = SuspendedDeepLCredentialValidator()
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: fixture.defaults),
            defaults: fixture.defaults,
            credentialValidator: validator
        )

        let firstSave = Task { @MainActor in
            await store.saveCredential("first-candidate")
        }
        await validator.waitUntilValidationStarts()
        #expect(store.isVerifyingCredential)

        let secondResult = await store.saveCredential("second-candidate")
        guard case let .failure(secondError) = secondResult else {
            Issue.record("Expected the second save to be rejected while verification runs.")
            return
        }
        #expect(secondError == .verificationInProgress)
        #expect(await validator.validationCount == 1)
        #expect(credentialStore.lastWrittenCredential == nil)

        await validator.finish(with: .success(()))
        guard case .success = await firstSave.value else {
            Issue.record("Expected the first save to finish successfully.")
            return
        }
        #expect(store.isVerifyingCredential == false)
        #expect(credentialStore.lastWrittenCredential == "first-candidate")
    }

    @Test @MainActor func revokingAuthorizationDisablesTranslateButKeepsCredentialInKeychain() {
        let fixture = isolatedDefaults()
        let defaults = fixture.defaults
        defer { defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: "synthetic")
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        store.setNetworkAuthorization(true)

        store.setNetworkAuthorization(false)

        #expect(store.hasCredential)
        #expect(store.isNetworkAuthorized == false)
        #expect(store.isConfigured == false)
        #expect(credentialStore.deleteCount == 0)
    }

    @Test @MainActor func deletingCredentialDisablesTranslateWithoutChangingGrant() {
        let fixture = isolatedDefaults()
        let defaults = fixture.defaults
        defer { defaults.removePersistentDomain(forName: fixture.suiteName) }
        let credentialStore = RecordingCredentialStore(value: "synthetic")
        let store = TranslateSettingsStore(
            credentialStore: credentialStore,
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        store.setNetworkAuthorization(true)

        let deleteResult = store.deleteCredential()
        guard case .success = deleteResult else {
            Issue.record("Expected credential deletion to succeed.")
            return
        }

        #expect(store.hasCredential == false)
        #expect(store.isNetworkAuthorized)
        #expect(store.isConfigured == false)
        #expect(credentialStore.deleteCount == 1)
    }

    private func isolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "TranslateSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private struct FixedDeepLCredentialValidator: DeepLCredentialValidating {
    let result: Result<Void, DeepLCredentialValidationError>

    func validate(
        _ credential: String
    ) async -> Result<Void, DeepLCredentialValidationError> {
        result
    }
}

private actor SuspendedDeepLCredentialValidator: DeepLCredentialValidating {
    private(set) var validationCount = 0
    private var continuation: CheckedContinuation<
        Result<Void, DeepLCredentialValidationError>,
        Never
    >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func validate(
        _ credential: String
    ) async -> Result<Void, DeepLCredentialValidationError> {
        validationCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilValidationStarts() async {
        guard validationCount == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(with result: Result<Void, DeepLCredentialValidationError>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
