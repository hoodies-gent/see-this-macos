import Combine
import Foundation

struct LensEditorDraft: Identifiable, Equatable {
    static let maximumDisplayNameWeight = 30
    static let displayNameCaption = "Name can be up to 30 characters."
    static let displayNameLimitReachedMessage = "Name reached maximum length (30 characters)."
    static let limitReachedFlashDurationNanoseconds: UInt64 = 1_500_000_000

    let lensID: String?
    var displayName: String
    var preference: String

    var id: String { lensID ?? "new-custom-lens" }

    init(lens: ExplanationLens? = nil) {
        lensID = lens?.id
        displayName = lens?.displayName ?? ""
        preference = lens?.preference ?? ""
    }

    static func displayNameWeight(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { $0 + weight(for: $1) }
    }

    static func clampDisplayName(_ value: String) -> String {
        var running = 0
        var clamped = String()
        clamped.reserveCapacity(value.utf8.count)
        for character in value {
            let contribution = character.unicodeScalars.reduce(0) { $0 + weight(for: $1) }
            guard running + contribution <= maximumDisplayNameWeight else { break }
            clamped.append(character)
            running += contribution
        }
        return clamped
    }

    static func insertingTargetLanguageVariable(into preference: String) -> String {
        let variable = ExplanationLens.targetLanguageVariable
        guard !preference.contains(variable) else { return preference }
        guard !preference.isEmpty else { return variable }
        let separator = preference.last?.isWhitespace == true ? "" : " "
        return preference + separator + variable
    }

    var displayNameIsWithinLimit: Bool {
        Self.displayNameWeight(displayName) <= Self.maximumDisplayNameWeight
    }

    private static func weight(for scalar: Unicode.Scalar) -> Int {
        isFullWidth(scalar) ? 2 : 1
    }

    private static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        // East Asian Wide / Fullwidth Unicode ranges — no fractional widths, kept as small ranges.
        switch scalar.value {
        case 0x1100...0x115F,
             0x2E80...0x303E,
             0x3041...0x33FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xA000...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE30...0xFE4F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x20000...0x2FFFD,
             0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class LensStore: ObservableObject {
    private struct StoredSettings: Codable {
        let catalogVersion: Int?
        let customLenses: [ExplanationLens]
        let removedBuiltInLensIDs: [String]?
        let inlineLensIDs: [String]?
        let defaultLensID: String?
        let selectedOllamaModel: String?
        let lensOrder: [String]?
    }

    static let maximumInlineLenses = 6
    private static let currentCatalogVersion = 1
    private static let storageKey = "explanationLensSettings"

    @Published private(set) var customLenses: [ExplanationLens]
    @Published private(set) var removedBuiltInLensIDs: [String]
    @Published private(set) var inlineLensIDs: [String]
    @Published private(set) var defaultLensID: String?
    @Published private(set) var selectedOllamaModel: String
    @Published private(set) var orderedLensIDs: [String]
    private let defaults: UserDefaults
    private let knownPackageLensIDs: [String]

    init(
        defaults: UserDefaults = .standard,
        knownPackageLensIDs: [String] = [TranslateActionCoordinator.actionID]
    ) {
        self.defaults = defaults
        self.knownPackageLensIDs = Self.uniqueIDs(knownPackageLensIDs)
        let freshCatalogIDs = Self.uniqueIDs(
            ExplanationLens.allCases.map(\.id)
                + [ExplanationLens.localTranslateID]
                + self.knownPackageLensIDs
        )
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let settings = try? JSONDecoder().decode(StoredSettings.self, from: data)
        else {
            customLenses = []
            removedBuiltInLensIDs = []
            inlineLensIDs = ExplanationLens.allCases.map(\.id)
                + [ExplanationLens.localTranslateID]
            defaultLensID = nil
            selectedOllamaModel = OllamaProvider.defaultModelName
            orderedLensIDs = freshCatalogIDs
            return
        }

        let builtInIDs = Set(ExplanationLens.allCases.map(\.id))
        let removedBuiltIns = Set(settings.removedBuiltInLensIDs ?? []).intersection(builtInIDs)
        let loadedCustomLenses = settings.customLenses.filter { !$0.isBuiltIn }
        let availableIDs = Set(
            ExplanationLens.allCases
                .filter { !removedBuiltIns.contains($0.id) }
                .map(\.id)
                + loadedCustomLenses.map(\.id)
                + [ExplanationLens.localTranslateID]
                + self.knownPackageLensIDs
        )
        let requestedInlineIDs = settings.inlineLensIDs ?? ExplanationLens.allCases.map(\.id)
        customLenses = loadedCustomLenses
        removedBuiltInLensIDs = ExplanationLens.allCases.map(\.id).filter { removedBuiltIns.contains($0) }
        let defaultOrder = Self.uniqueIDs(
            ExplanationLens.allCases.map(\.id)
                + loadedCustomLenses.map(\.id)
                + [ExplanationLens.localTranslateID]
                + self.knownPackageLensIDs
        )
        let reconciledOrder = Self.reconcileOrder(settings.lensOrder ?? [], availableIDs: availableIDs, fallbackOrder: defaultOrder)
        orderedLensIDs = reconciledOrder
        let validInlineIDs = Self.validInlineIDs(from: requestedInlineIDs, availableIDs: availableIDs)
        // Stored inline IDs can all refer to built-ins that no longer exist; never load with none.
        var resolvedInlineIDs = validInlineIDs.isEmpty
            ? Array(reconciledOrder.prefix(Self.maximumInlineLenses))
            : validInlineIDs
        if settings.catalogVersion == nil,
           !resolvedInlineIDs.contains(ExplanationLens.localTranslateID),
           resolvedInlineIDs.count < Self.maximumInlineLenses {
            resolvedInlineIDs.append(ExplanationLens.localTranslateID)
        }
        inlineLensIDs = resolvedInlineIDs
        defaultLensID = settings.defaultLensID.flatMap { resolvedInlineIDs.contains($0) ? $0 : nil }
        selectedOllamaModel = settings.selectedOllamaModel ?? OllamaProvider.defaultModelName
    }

    var lenses: [ExplanationLens] {
        let byID = Dictionary(
            uniqueKeysWithValues:
                (ExplanationLens.allCases.filter { !removedBuiltInLensIDs.contains($0.id) } + customLenses)
                    .map { ($0.id, $0) }
        )
        return orderedLensIDs.compactMap { byID[$0] }
    }

    func lens(id: String) -> ExplanationLens? {
        if id == ExplanationLens.localTranslateID {
            return ExplanationLens.localTranslateCatalogEntry
        }
        return lenses.first { $0.id == id }
    }

    var hasRemovedBuiltInLenses: Bool { !removedBuiltInLensIDs.isEmpty }

    func isLensNameAvailable(_ displayName: String, excludingID: String? = nil) -> Bool {
        let candidate = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return !(ExplanationLens.allCases + [ExplanationLens.localTranslateCatalogEntry] + customLenses).contains {
            $0.id != excludingID
                && $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) == candidate
        }
    }

    var inlineLenses: [ExplanationLens] {
        let byID = Dictionary(uniqueKeysWithValues: lenses.map { ($0.id, $0) })
        return orderedLensIDs.compactMap { id in
            inlineLensIDs.contains(id) ? byID[id] : nil
        }
    }

    var defaultLens: ExplanationLens? {
        guard let defaultLensID else { return nil }
        return inlineLenses.first(where: { $0.id == defaultLensID })
    }

    @discardableResult
    func addCustomLens(displayName: String, preference: String) -> ExplanationLens {
        let lens = ExplanationLens.custom(displayName: displayName, preference: preference)
        customLenses.append(lens)
        orderedLensIDs.append(lens.id)
        persist()
        return lens
    }

    func updateCustomLens(id: String, displayName: String, preference: String) {
        guard let index = customLenses.firstIndex(where: { $0.id == id }) else { return }
        customLenses[index] = ExplanationLens(
            id: id,
            displayName: displayName,
            preference: preference,
            kind: .custom
        )
        persist()
    }

    func removeLens(id: String) -> Bool {
        guard lenses.contains(where: { $0.id == id }), lenses.count > 1 else { return false }

        if ExplanationLens.allCases.contains(where: { $0.id == id }) {
            removedBuiltInLensIDs.append(id)
        } else {
            customLenses.removeAll { $0.id == id }
            orderedLensIDs.removeAll { $0 == id }
        }
        inlineLensIDs.removeAll { $0 == id }
        if defaultLensID == id {
            defaultLensID = nil
        }
        if inlineLensIDs.isEmpty, let fallbackID = orderedLensIDs.first {
            inlineLensIDs = [fallbackID]
        }
        persist()
        return true
    }

    func restoreBuiltInLenses() {
        guard hasRemovedBuiltInLenses else { return }
        removedBuiltInLensIDs = []
        for builtInID in ExplanationLens.allCases.map(\.id) where !orderedLensIDs.contains(builtInID) {
            orderedLensIDs.append(builtInID)
        }
        persist()
    }

    func moveLens(id: String, toIndex targetIndex: Int) {
        var updated = orderedLensIDs
        guard let currentIndex = updated.firstIndex(of: id) else { return }
        let boundedTarget = max(0, min(targetIndex, updated.count))
        guard currentIndex != boundedTarget, currentIndex + 1 != boundedTarget else { return }
        let value = updated.remove(at: currentIndex)
        let insertionIndex = boundedTarget > currentIndex ? boundedTarget - 1 : boundedTarget
        updated.insert(value, at: insertionIndex)
        orderedLensIDs = updated
        persist()
    }

    @discardableResult
    func setInlineLens(id: String, isEnabled: Bool) -> Bool {
        guard orderedLensIDs.contains(id) else { return false }
        if isEnabled {
            guard inlineLensIDs.contains(id) || inlineLensIDs.count < Self.maximumInlineLenses else {
                return false
            }
            if !inlineLensIDs.contains(id) {
                if let lastVisibleID = orderedLensIDs.last(where: { inlineLensIDs.contains($0) }),
                   let currentIndex = orderedLensIDs.firstIndex(of: id),
                   let lastVisibleIndex = orderedLensIDs.firstIndex(of: lastVisibleID),
                   currentIndex < lastVisibleIndex {
                    orderedLensIDs.remove(at: currentIndex)
                    let insertionIndex = (orderedLensIDs.firstIndex(of: lastVisibleID) ?? 0) + 1
                    orderedLensIDs.insert(id, at: insertionIndex)
                }
                inlineLensIDs.append(id)
            }
        } else {
            guard !inlineLensIDs.contains(id) || inlineLensIDs.count > 1 else {
                return false
            }
            inlineLensIDs.removeAll { $0 == id }
            if defaultLensID == id {
                defaultLensID = nil
            }
        }
        persist()
        return true
    }

    func setDefaultLens(id: String?) {
        defaultLensID = id.flatMap { inlineLensIDs.contains($0) ? $0 : nil }
        persist()
    }

    func invalidateLens(id: String) {
        let wasVisible = inlineLensIDs.contains(id)
        let wasDefault = defaultLensID == id
        inlineLensIDs.removeAll { $0 == id }
        if wasDefault {
            defaultLensID = nil
        }
        if inlineLensIDs.isEmpty,
           let fallbackID = orderedLensIDs.first(where: { candidateID in
               candidateID != id && lens(id: candidateID) != nil
           }) {
            inlineLensIDs = [fallbackID]
        }
        if wasVisible || wasDefault {
            persist()
        }
    }

    func setSelectedOllamaModel(_ model: String) {
        selectedOllamaModel = model
        persist()
    }

    private static func reconcileOrder(
        _ storedOrder: [String],
        availableIDs: Set<String>,
        fallbackOrder: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in storedOrder where availableIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in fallbackOrder where availableIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private static func validInlineIDs(from ids: [String], availableIDs: Set<String>) -> [String] {
        var uniqueIDs: [String] = []
        for id in ids where availableIDs.contains(id) && !uniqueIDs.contains(id) {
            guard uniqueIDs.count < maximumInlineLenses else { break }
            uniqueIDs.append(id)
        }
        return uniqueIDs
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func persist() {
        let settings = StoredSettings(
            catalogVersion: Self.currentCatalogVersion,
            customLenses: customLenses,
            removedBuiltInLensIDs: removedBuiltInLensIDs,
            inlineLensIDs: inlineLensIDs,
            defaultLensID: defaultLensID,
            selectedOllamaModel: selectedOllamaModel,
            lensOrder: orderedLensIDs
        )
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
