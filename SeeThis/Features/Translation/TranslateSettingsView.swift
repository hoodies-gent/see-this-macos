import SwiftUI

struct TranslateTargetLanguagePicker: View {
    @ObservedObject var store: TranslateSettingsStore
    var onChange: () -> Void = {}

    var body: some View {
        Picker(
            "Translation target",
            selection: Binding(
                get: { store.selectedLanguageOptionID },
                set: {
                    store.setTargetLanguage($0)
                    onChange()
                }
            )
        ) {
            ForEach(TranslateSettingsStore.languageOptions) { option in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 240, alignment: .leading)
    }
}

struct TranslateSettingsView: View {
    @ObservedObject var store: TranslateSettingsStore
    var onConfigurationChanged: () -> Void = {}
    @State private var credentialDraft = ""
    @State private var isEditingCredential = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DeepL · \(TranslateSettingsStore.endpoint.host) · selected text and language codes")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.hasCredential && !isEditingCredential {
                HStack(spacing: 8) {
                    Label("API key saved (••••••••)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Change key") {
                        credentialDraft = ""
                        isEditingCredential = true
                    }
                    .disabled(store.isVerifyingCredential)
                    Button("Remove saved key") {
                        removeCredential()
                    }
                    .disabled(store.isVerifyingCredential)
                }
            } else {
                SecureField("Enter API key", text: $credentialDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.isVerifyingCredential)
                HStack(spacing: 8) {
                    Button(store.isVerifyingCredential ? "Verifying…" : "Save in Keychain") {
                        saveCredential()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        credentialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || store.isVerifyingCredential
                    )

                    if store.hasCredential {
                        Button("Cancel") {
                            credentialDraft = ""
                            isEditingCredential = false
                        }
                        .disabled(store.isVerifyingCredential)
                    }
                }
                if !store.hasCredential {
                    Text("No saved key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(
                "Allow Translate with DeepL to send selected text to \(TranslateSettingsStore.endpoint.host)",
                isOn: Binding(
                    get: { store.isNetworkAuthorized },
                    set: {
                        store.setNetworkAuthorization($0)
                        onConfigurationChanged()
                    }
                )
            )
            .disabled(!store.hasCredential)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        }
    }

    private func saveCredential() {
        Task {
            switch await store.saveCredential(credentialDraft) {
            case .success:
                credentialDraft = ""
                isEditingCredential = false
                statusIsError = false
                statusMessage = "API key verified and saved in Keychain."
                onConfigurationChanged()
            case let .failure(error):
                statusIsError = true
                statusMessage = credentialSaveErrorMessage(error)
            }
        }
    }

    private func removeCredential() {
        switch store.deleteCredential() {
        case .success:
            store.setNetworkAuthorization(false)
            credentialDraft = ""
            isEditingCredential = false
            statusIsError = false
            statusMessage = "Credential removed from Keychain."
            onConfigurationChanged()
        case let .failure(error):
            statusIsError = true
            statusMessage = credentialErrorMessage(error)
        }
    }

    private func credentialErrorMessage(_ error: CredentialStoreError) -> String {
        switch error {
        case .invalidCredential:
            "Enter a non-empty API key."
        case .keychainFailure:
            "Could not update the Keychain credential."
        }
    }

    private func credentialSaveErrorMessage(_ error: TranslateCredentialSaveError) -> String {
        switch error {
        case .verificationInProgress:
            "API key verification is already in progress."
        case let .keychain(error):
            credentialErrorMessage(error)
        case let .validation(error):
            switch error {
            case .invalidCredential, .rejected:
                "DeepL rejected this API key."
            case .timeout, .transport:
                "Could not reach DeepL. Check your connection and try again."
            case .cancelled:
                "API key verification was cancelled."
            case .invalidResponse, .providerRejected:
                "DeepL could not verify this API key right now."
            }
        }
    }
}
