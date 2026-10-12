import Foundation

nonisolated enum ResolvedActionSource: Equatable, Sendable {
    case lens
    case package(version: SemanticVersion)
}

nonisolated enum ModelPromptFraming: Equatable, Sendable {
    case productOwned
    case readerAuthored
}

nonisolated enum ResolvedActionExecution: Equatable, Sendable {
    case modelPrompt(
        prompt: String,
        framing: ModelPromptFraming = .productOwned
    )
    case singleCapability(capabilityID: String)
    case boundedAgent(prompt: String, capabilityIDs: [String])
}

nonisolated struct ResolvedAction: Equatable, Sendable {
    let id: String
    let source: ResolvedActionSource
    let display: ActionDisplayInfo
    let input: ActionInputRequirement
    let execution: ResolvedActionExecution
    let resolvedPermissions: [ActionPermission]
    let budget: ActionBudget
    let output: ActionOutputContract
}

enum ReaderAction: Equatable, Identifiable {
    case lens(ExplanationLens)
    case package(ResolvedAction)

    var id: String {
        switch self {
        case let .lens(lens): lens.id
        case let .package(action): action.id
        }
    }

    var display: ActionDisplayInfo {
        switch self {
        case let .lens(lens):
            ActionDisplayInfo(name: lens.displayName, allowsFollowUp: lens.allowsFollowUp)
        case let .package(action):
            action.display
        }
    }

    @MainActor
    func resolvedAction() -> ResolvedAction {
        switch self {
        case let .lens(lens):
            LensActionResolver.resolve(lens)
        case let .package(action):
            action
        }
    }
}

nonisolated enum ReaderActionDisabledReason: Equatable {
    case externalActionNotConfigured
}

struct ReaderActionOption: Equatable, Identifiable {
    let action: ReaderAction
    let availability: ReaderActionAvailability

    var id: String { action.id }
    var display: ActionDisplayInfo { action.display }
    var isEnabled: Bool {
        availability == .enabled
    }
}

nonisolated enum ReaderActionAvailability: Equatable {
    case enabled
    case disabled(reason: ReaderActionDisabledReason)
}

enum ReaderActionCatalog {
    static func resolve(
        lenses: [ExplanationLens],
        packages: [LoadedActionPackage]
    ) -> [ReaderAction] {
        let lensActions = lenses.map(ReaderAction.lens)
        let packageActions = packages.compactMap { package -> ReaderAction? in
            guard case let .resolved(action) = PackageActionResolver.resolve(package) else {
                return nil
            }
            return .package(action)
        }
        return lensActions + packageActions
    }

    static func options(
        actions: [ReaderAction],
        orderedIDs: [String],
        visibleIDs: [String],
        enabledPackageIDs: Set<String>
    ) -> [ReaderActionOption] {
        let visibleIDSet = Set(visibleIDs)
        let actionsByID = Dictionary(
            actions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return orderedIDs.compactMap { id in
            guard visibleIDSet.contains(id), let action = actionsByID[id] else {
                return nil
            }
            if case .package = action, !enabledPackageIDs.contains(id) {
                return nil
            }
            return ReaderActionOption(action: action, availability: .enabled)
        }
    }

    static func options(
        lenses: [ExplanationLens],
        packages: [LoadedActionPackage],
        enabledPackageIDs: Set<String>
    ) -> [ReaderActionOption] {
        resolve(lenses: lenses, packages: packages).map { action in
            let availability: ReaderActionAvailability
            switch action {
            case .lens:
                availability = .enabled
            case let .package(package):
                availability = enabledPackageIDs.contains(package.id)
                    ? .enabled
                    : .disabled(reason: .externalActionNotConfigured)
            }
            return ReaderActionOption(action: action, availability: availability)
        }
    }
}

nonisolated struct LensActionProjection: Equatable, Sendable {
    let actions: [ResolvedAction]
    let inlineActionIDs: [String]
    let defaultActionID: String?
}
