enum ModelInstallCancellationPolicy {
    static func shouldDeletePartialModel(
        state: ModelInstallState?,
        modelWasPresentBeforeInstall: Bool
    ) -> Bool {
        guard !modelWasPresentBeforeInstall else { return false }

        switch state {
        case .queued, .pulling, .paused:
            return true
        case .failed, nil:
            return false
        }
    }
}
