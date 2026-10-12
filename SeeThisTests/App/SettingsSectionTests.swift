import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct SettingsSectionTests {

    @Test @MainActor func productSettingsSectionsStartWithGeneral() {
        #expect(SettingsSection.productSections == [.general, .models, .lenses])
    }

    @Test @MainActor func accessibilityCopyDescribesTheAppMacOSAuthorization() {
        #expect(
            SettingsSection.general.accessibilityDescription
                == "Allow SeeThis to read selected text from the frontmost app."
        )
    }

    @Test @MainActor func shortcutCopyDescribesUniversalCapture() {
        #expect(
            SettingsSection.general.shortcutDescription
                == "Press ⌘D in any app. Selected text is captured automatically."
        )
    }

    @Test @MainActor func shortcutDisplayCanBeRenderedAsSeparateKeycaps() {
        #expect(KeyboardShortcut.commandD.displayParts == ["⌘", "D"])
    }

    @Test @MainActor func settingsNavigationRequestIsConsumedOnce() {
        let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SettingsNavigation.consumeRequestedSection(defaults: defaults) == nil)

        SettingsNavigation.request(.lenses, defaults: defaults)

        #expect(SettingsNavigation.consumeRequestedSection(defaults: defaults) == .lenses)
        #expect(SettingsNavigation.consumeRequestedSection(defaults: defaults) == nil)
    }

    @Test @MainActor func openingLensesSettingsInvokesTheSettingsWindowAction() {
        let suiteName = "SettingsNavigationOpenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var didOpenSettings = false

        SettingsNavigation.openLensesSettings(
            defaults: defaults,
            openSettingsWindow: { didOpenSettings = true }
        )

        #expect(didOpenSettings)
        #expect(SettingsNavigation.consumeRequestedSection(defaults: defaults) == .lenses)
    }

}
