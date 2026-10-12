import Foundation

@MainActor
enum LensActionResolver {
    static func project(
        store: LensStore,
        targetLanguage: String
    ) -> LensActionProjection {
        let actions = store.orderedLensIDs.compactMap { id -> ResolvedAction? in
            guard let lens = store.lens(id: id) else { return nil }
            return resolve(lens, targetLanguage: targetLanguage)
        }
        let availableActionIDs = Set(actions.map(\.id))
        let inlineIDSet = Set(store.inlineLensIDs)
        return LensActionProjection(
            actions: actions,
            inlineActionIDs: store.orderedLensIDs.filter {
                inlineIDSet.contains($0) && availableActionIDs.contains($0)
            },
            defaultActionID: store.defaultLensID.flatMap {
                availableActionIDs.contains($0) ? $0 : nil
            }
        )
    }

    static func resolve(
        _ lens: ExplanationLens,
        targetLanguage: String? = nil
    ) -> ResolvedAction {
        let prompt = targetLanguage.map {
            lens.renderedPreference(targetLanguage: $0)
        } ?? lens.preference
        return ResolvedAction(
            id: lens.id,
            source: .lens,
            display: ActionDisplayInfo(
                name: lens.displayName,
                allowsFollowUp: lens.allowsFollowUp
            ),
            input: ActionInputRequirement(selection: .required),
            execution: .modelPrompt(
                prompt: prompt,
                framing: lens.isBuiltIn ? .productOwned : .readerAuthored
            ),
            resolvedPermissions: [.localModel],
            budget: ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0),
            output: ActionOutputContract(kind: .text, format: .markdown)
        )
    }
}
