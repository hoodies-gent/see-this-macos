import Combine
import Foundation

struct TranslateLanguageOption: Identifiable, Hashable {
    let id: String
    let displayName: String
}

nonisolated enum TranslateCredentialSaveError: Error, Equatable, Sendable {
    case verificationInProgress
    case validation(DeepLCredentialValidationError)
    case keychain(CredentialStoreError)
}

@MainActor
final class TranslateSettingsStore: ObservableObject {
    static let actionID = TranslateActionCoordinator.actionID
    static let endpoint = DeepLEndpoint.free
    static let targetLanguageDefaultsKey = "translate.targetLanguage"
    static let systemLanguageOptionID = "SYSTEM"

    static let languageOptions: [TranslateLanguageOption] = [
        TranslateLanguageOption(id: systemLanguageOptionID, displayName: "System Language"),
        TranslateLanguageOption(id: "AR", displayName: "Arabic"),
        TranslateLanguageOption(id: "BG", displayName: "Bulgarian"),
        TranslateLanguageOption(id: "ZH-HANS", displayName: "Chinese (Simplified)"),
        TranslateLanguageOption(id: "ZH-HANT", displayName: "Chinese (Traditional)"),
        TranslateLanguageOption(id: "CS", displayName: "Czech"),
        TranslateLanguageOption(id: "DA", displayName: "Danish"),
        TranslateLanguageOption(id: "NL", displayName: "Dutch"),
        TranslateLanguageOption(id: "EN-GB", displayName: "English (UK)"),
        TranslateLanguageOption(id: "EN-US", displayName: "English (US)"),
        TranslateLanguageOption(id: "ET", displayName: "Estonian"),
        TranslateLanguageOption(id: "FI", displayName: "Finnish"),
        TranslateLanguageOption(id: "FR", displayName: "French"),
        TranslateLanguageOption(id: "DE", displayName: "German"),
        TranslateLanguageOption(id: "EL", displayName: "Greek"),
        TranslateLanguageOption(id: "HE", displayName: "Hebrew"),
        TranslateLanguageOption(id: "HU", displayName: "Hungarian"),
        TranslateLanguageOption(id: "ID", displayName: "Indonesian"),
        TranslateLanguageOption(id: "IT", displayName: "Italian"),
        TranslateLanguageOption(id: "JA", displayName: "Japanese"),
        TranslateLanguageOption(id: "KO", displayName: "Korean"),
        TranslateLanguageOption(id: "LV", displayName: "Latvian"),
        TranslateLanguageOption(id: "LT", displayName: "Lithuanian"),
        TranslateLanguageOption(id: "NB", displayName: "Norwegian Bokmål"),
        TranslateLanguageOption(id: "PL", displayName: "Polish"),
        TranslateLanguageOption(id: "PT-BR", displayName: "Portuguese (Brazil)"),
        TranslateLanguageOption(id: "PT-PT", displayName: "Portuguese (Portugal)"),
        TranslateLanguageOption(id: "RO", displayName: "Romanian"),
        TranslateLanguageOption(id: "RU", displayName: "Russian"),
        TranslateLanguageOption(id: "SK", displayName: "Slovak"),
        TranslateLanguageOption(id: "SL", displayName: "Slovenian"),
        TranslateLanguageOption(id: "ES", displayName: "Spanish"),
        TranslateLanguageOption(id: "ES-419", displayName: "Spanish (Latin America)"),
        TranslateLanguageOption(id: "SV", displayName: "Swedish"),
        TranslateLanguageOption(id: "TH", displayName: "Thai"),
        TranslateLanguageOption(id: "TR", displayName: "Turkish"),
        TranslateLanguageOption(id: "UK", displayName: "Ukrainian"),
        TranslateLanguageOption(id: "VI", displayName: "Vietnamese")
    ]

    /// DeepL's `target_lang` rejects bare codes for languages with regional
    /// variants (e.g. plain `EN` or `ZH`), so the system-language fallback
    /// must resolve to one of the exact variant codes above.
    static var systemTargetLanguageCode: String {
        switch Locale.current.language.languageCode?.identifier.lowercased() {
        case "en": return "EN-US"
        case "pt": return "PT-PT"
        case "zh": return "ZH-HANS"
        case let code?:
            let candidate = code.uppercased()
            return languageOptions.contains { $0.id == candidate } ? candidate : "EN-US"
        case nil:
            return "EN-US"
        }
    }

    static var requiredPermission: ActionPermission {
        DeepLTranslationCapability.requiredPermission(for: endpoint)
    }

    @Published private(set) var hasCredential = false
    @Published private(set) var isNetworkAuthorized = false
    @Published private(set) var isVerifyingCredential = false
    @Published private(set) var selectedLanguageOptionID: String

    var targetLanguageCode: String {
        selectedLanguageOptionID == Self.systemLanguageOptionID
            ? Self.systemTargetLanguageCode
            : selectedLanguageOptionID
    }

    /// Human-readable name of the resolved target language, for use in
    /// natural-language prompts (the local Translate lens) rather than
    /// provider-specific codes like "ZH-HANS" or "EN-US".
    var targetLanguageDisplayName: String {
        let code = targetLanguageCode
        return Self.languageOptions.first { $0.id == code }?.displayName ?? code
    }

    var isConfigured: Bool {
        hasCredential && isNetworkAuthorized
    }

    private let credentialStore: any CredentialStore
    private let grantStore: ActionPermissionGrantStore
    private let defaults: UserDefaults
    private let credentialValidator: any DeepLCredentialValidating
    let lensStore: LensStore

    init(
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        grantStore: ActionPermissionGrantStore = ActionPermissionGrantStore(),
        defaults: UserDefaults = .standard,
        lensStore: LensStore? = nil,
        credentialValidator: any DeepLCredentialValidating = DeepLCredentialValidator(
            transport: URLSessionDeepLTransport(),
            endpoint: .free
        )
    ) {
        self.credentialStore = credentialStore
        self.grantStore = grantStore
        self.defaults = defaults
        self.lensStore = lensStore ?? LensStore(defaults: defaults)
        self.credentialValidator = credentialValidator
        selectedLanguageOptionID = Self.systemLanguageOptionID
        refresh()
    }

    func refresh() {
        if case let .success(credential) = credentialStore.read(
            DeepLTranslationCapability.credentialKey
        ) {
            hasCredential = credential?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } else {
            hasCredential = false
        }
        isNetworkAuthorized = grantStore
            .permissions(for: Self.actionID)
            .contains(Self.requiredPermission)
        selectedLanguageOptionID = Self.normalizeLanguageOption(
            defaults.string(forKey: Self.targetLanguageDefaultsKey)
        ) ?? Self.systemLanguageOptionID
        if !isConfigured {
            invalidateDeepLLens()
        }
    }

    func setTargetLanguage(_ optionID: String) {
        guard let normalized = Self.normalizeLanguageOption(optionID) else { return }
        defaults.set(normalized, forKey: Self.targetLanguageDefaultsKey)
        selectedLanguageOptionID = normalized
    }

    func saveCredential(
        _ credential: String
    ) async -> Result<Void, TranslateCredentialSaveError> {
        guard !isVerifyingCredential else {
            return .failure(.verificationInProgress)
        }

        isVerifyingCredential = true
        defer { isVerifyingCredential = false }

        let candidate = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        switch await credentialValidator.validate(candidate) {
        case let .failure(error):
            return .failure(.validation(error))
        case .success:
            let result = credentialStore
                .write(candidate, for: DeepLTranslationCapability.credentialKey)
                .mapError(TranslateCredentialSaveError.keychain)
            if case .success = result {
                refresh()
            }
            return result
        }
    }

    func deleteCredential() -> Result<Void, CredentialStoreError> {
        let result = credentialStore.delete(DeepLTranslationCapability.credentialKey)
        if case .success = result {
            refresh()
        }
        return result
    }

    func setNetworkAuthorization(_ isAuthorized: Bool) {
        grantStore.setPermissions(
            isAuthorized ? [Self.requiredPermission] : [],
            for: Self.actionID
        )
        refresh()
    }

    @discardableResult
    func setDeepLLensVisible(_ isVisible: Bool) -> Bool {
        guard !isVisible || isConfigured else { return false }
        return lensStore.setInlineLens(id: Self.actionID, isEnabled: isVisible)
    }

    func invalidateDeepLLens() {
        lensStore.invalidateLens(id: Self.actionID)
    }

    func permissionGrants() -> ActionPermissionGrants {
        ActionPermissionGrants([
            Self.actionID: grantStore.permissions(for: Self.actionID)
        ])
    }

    private static func normalizeLanguageOption(_ optionID: String?) -> String? {
        guard let optionID else { return nil }
        let normalized = optionID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return languageOptions.contains { $0.id == normalized } ? normalized : nil
    }
}
