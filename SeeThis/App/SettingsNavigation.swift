import Foundation

extension Notification.Name {
    static let seeThisSettingsSectionRequested = Notification.Name(
        "SeeThis.settingsSectionRequested"
    )
    static let seeThisSettingsWindowRequested = Notification.Name(
        "SeeThis.settingsWindowRequested"
    )
}

enum SettingsNavigation {
    private static let requestedSectionKey = "pendingSettingsSection"

    static func request(
        _ section: SettingsSection,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(section.rawValue, forKey: requestedSectionKey)
        NotificationCenter.default.post(
            name: .seeThisSettingsSectionRequested,
            object: section
        )
    }

    // The overlay lives in an AppKit panel with no scene environment, so it asks the menu bar scene to open the window.
    static func requestSettingsWindow() {
        NotificationCenter.default.post(name: .seeThisSettingsWindowRequested, object: nil)
    }

    static func openLensesSettings(
        defaults: UserDefaults = .standard,
        openSettingsWindow: () -> Void
    ) {
        request(.lenses, defaults: defaults)
        openSettingsWindow()
    }

    static func consumeRequestedSection(
        defaults: UserDefaults = .standard
    ) -> SettingsSection? {
        defer { defaults.removeObject(forKey: requestedSectionKey) }
        guard let rawValue = defaults.string(forKey: requestedSectionKey) else {
            return nil
        }
        return SettingsSection(rawValue: rawValue)
    }

}
