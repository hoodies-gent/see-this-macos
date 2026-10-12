import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct TranslateOverlayTests {

    @Test @MainActor func overlayLensListIncludesLocalTranslateWithSavedTargetLanguage() {
        let suiteName = "HostContextDiagnostics-Translate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: nil),
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        settings.setTargetLanguage("ZH-HANS")
        let diagnostics = HostContextDiagnostics(translateSettings: settings)

        let actions = diagnostics.actionOptionsForOverlay().map(\.action)
        let lenses = actions.compactMap { action -> ExplanationLens? in
            guard case let .lens(lens) = action else { return nil }
            return lens
        }

        #expect(lenses.map(\.id) == [ExplanationLens.plain.id, "translate-local"])
        #expect(lenses.last?.preference.contains("Chinese (Simplified)") == true)
    }

    @Test @MainActor func overlayOmitsDeepLUntilCredentialGrantAndVisibilityAreAllPresent() {
        let suiteName = "HostContextDiagnostics-DeepL-Catalog-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lensStore = LensStore(defaults: defaults)
        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))

        let missingCredential = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: nil),
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        var diagnostics = HostContextDiagnostics(
            lensStore: lensStore,
            translateSettings: missingCredential
        )
        #expect(!diagnostics.actionOptionsForOverlay().map(\.id).contains("translate"))
        #expect(!lensStore.inlineLensIDs.contains("translate"))

        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))
        let configured = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: "synthetic-key"),
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        diagnostics = HostContextDiagnostics(
            lensStore: lensStore,
            translateSettings: configured
        )
        #expect(!diagnostics.actionOptionsForOverlay().map(\.id).contains("translate"))

        configured.setNetworkAuthorization(true)
        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))
        lensStore.moveLens(id: TranslateSettingsStore.actionID, toIndex: 0)
        #expect(
            diagnostics.actionOptionsForOverlay().map(\.id)
                == ["translate", "plain", "translate-local"]
        )

        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: false))
        #expect(!diagnostics.actionOptionsForOverlay().map(\.id).contains("translate"))
    }

    @Test @MainActor func configuredVisibleDeepLCanBeTheResolvedDefaultAction() throws {
        let suiteName = "HostContextDiagnostics-DeepL-Default-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lensStore = LensStore(defaults: defaults)
        let settings = TranslateSettingsStore(
            credentialStore: RecordingCredentialStore(value: "synthetic-key"),
            grantStore: ActionPermissionGrantStore(defaults: defaults),
            defaults: defaults
        )
        settings.setNetworkAuthorization(true)
        #expect(lensStore.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))
        lensStore.setDefaultLens(id: TranslateSettingsStore.actionID)
        let diagnostics = HostContextDiagnostics(
            lensStore: lensStore,
            translateSettings: settings
        )

        let action = try #require(diagnostics.defaultActionForOverlay())

        guard case let .package(resolvedAction) = action else {
            Issue.record("Expected the package-backed default action.")
            return
        }
        #expect(resolvedAction.id == TranslateSettingsStore.actionID)
        #expect(resolvedAction.execution == .singleCapability(capabilityID: "translate.deepl"))
    }

}
