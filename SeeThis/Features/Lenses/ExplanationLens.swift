import Foundation

struct ExplanationLens: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case builtIn
        case custom
    }

    let id: String
    let displayName: String
    let preference: String
    let kind: Kind
    let allowsFollowUp: Bool

    init(
        id: String,
        displayName: String,
        preference: String,
        kind: Kind,
        allowsFollowUp: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.preference = preference
        self.kind = kind
        self.allowsFollowUp = allowsFollowUp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        preference = try container.decode(String.self, forKey: .preference)
        kind = try container.decode(Kind.self, forKey: .kind)
        // Older stored custom lenses predate this field; default preserves the
        // pre-alpha rule that every lens accepts one follow-up.
        allowsFollowUp = try container.decodeIfPresent(Bool.self, forKey: .allowsFollowUp) ?? true
    }

    var isBuiltIn: Bool { kind == .builtIn }

    static let plain = ExplanationLens(
        id: "plain",
        displayName: "Explain",
        preference: "Explain what the selected text means in plain language for a newcomer, in at most three short sentences.",
        kind: .builtIn
    )
    static let tutorialDemo = ExplanationLens(
        id: "tutorial-demo",
        displayName: "Explain this",
        preference: "Explain the selected passage in concise, plain language. Start with what it means, then say why it matters if the passage supports that conclusion.",
        kind: .builtIn
    )

    static var allCases: [ExplanationLens] {
        [.plain]
    }

    static let targetLanguageVariable = "{{target_language}}"
    static let localTranslateID = "translate-local"
    static let localTranslateCatalogEntry = ExplanationLens(
        id: localTranslateID,
        displayName: "Translate",
        preference: "Translate the selected passage into {{target_language}}. Preserve academic terminology, proper nouns, symbols, formulas, citations, and formatting. Return only the translation; do not explain or summarize.",
        kind: .builtIn,
        allowsFollowUp: false
    )

    static func translation(targetLanguage: String) -> ExplanationLens {
        return ExplanationLens(
            id: localTranslateID,
            displayName: "Translate",
            preference: localTranslateCatalogEntry.renderedPreference(
                targetLanguage: targetLanguage
            ),
            kind: .builtIn,
            allowsFollowUp: false
        )
    }

    static func custom(displayName: String, preference: String) -> ExplanationLens {
        ExplanationLens(
            id: UUID().uuidString,
            displayName: displayName,
            preference: preference,
            kind: .custom
        )
    }

    var readerVisibleInstruction: String { preference }

    func renderedPreference(targetLanguage: String) -> String {
        preference.replacingOccurrences(
            of: Self.targetLanguageVariable,
            with: targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
