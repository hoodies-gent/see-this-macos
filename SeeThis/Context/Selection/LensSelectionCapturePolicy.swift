enum LensSelectionCapturePolicy {
    nonisolated static func shouldReuseActiveSnapshot(
        activeHostBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        appBundleIdentifier: String?
    ) -> Bool {
        guard let activeHostBundleIdentifier else { return false }
        return activeHostBundleIdentifier != frontmostBundleIdentifier
            || activeHostBundleIdentifier == appBundleIdentifier
    }
}
