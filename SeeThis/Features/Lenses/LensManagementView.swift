import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LensSaveFeedback: Equatable {
    case saved

    static let iconName = "checkmark.circle.fill"
    static let iconToMessageSpacing: CGFloat = 3
    static let displayDurationNanoseconds: UInt64 = 1_000_000_000

    var message: String {
        switch self {
        case .saved:
            "Saved"
        }
    }
}

enum LensEditorSaveNote {
    static let iconName = "info.circle"
    static let iconToMessageSpacing: CGFloat = 4
    static let message = "Changes apply to the next explanation."
}

struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .accessibilityLabel("Beta feature")
    }
}

private struct DefaultLensBadge: View {
    var body: some View {
        Text("Default")
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .accessibilityLabel("Default lens")
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                HoverHighlightRect(isHovering: isHovering)
            }
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private struct HoverHighlightRect: View {
    let isHovering: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if isHovering && isEnabled {
            RoundedRectangle(cornerRadius: LensHoverAppearance.cornerRadius)
                .fill(Color.primary.opacity(LensHoverAppearance.backgroundOpacity))
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

private struct LensRowDropDelegate: DropDelegate {
    let targetLensID: String
    @Binding var draggingLensID: String?
    let store: LensStore
    let onMove: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        reorderIfNeeded()
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingLensID = nil
        return true
    }

    @MainActor
    private func reorderIfNeeded() {
        guard let sourceLensID = draggingLensID, sourceLensID != targetLensID else { return }
        let ids = store.orderedLensIDs
        guard
            let sourceIndex = ids.firstIndex(of: sourceLensID),
            let targetIndex = ids.firstIndex(of: targetLensID)
        else {
            return
        }
        let insertionOffset = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveLens(id: sourceLensID, toIndex: insertionOffset)
        }
        onMove()
    }
}

private struct ManagedLensEntry: Identifiable {
    enum Kind {
        case prompt(ExplanationLens)
        case localTranslate
        case deepL
    }

    let id: String
    let displayName: String
    let kind: Kind
}

private struct LensContainerDropDelegate: DropDelegate {
    @Binding var draggingLensID: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingLensID = nil
        return true
    }
}

struct LensManagementView: View {
    @ObservedObject var store: LensStore
    @ObservedObject var translateSettings: TranslateSettingsStore
    let onLensesSaved: () -> Void
    @State private var editorDraft: LensEditorDraft?
    @State private var saveFeedback: LensSaveFeedback?
    @State private var saveFeedbackToken: UUID?
    @State private var expandedLensIDs: Set<String> = []
    @State private var pendingDelete: ExplanationLens?
    @State private var copyFeedbackLensID: String?
    @State private var draggingLensID: String?

    private var managedEntries: [ManagedLensEntry] {
        store.orderedLensIDs.compactMap { id in
            if id == ExplanationLens.localTranslateID {
                return ManagedLensEntry(
                    id: id,
                    displayName: ExplanationLens.localTranslateCatalogEntry.displayName,
                    kind: .localTranslate
                )
            }
            if id == TranslateSettingsStore.actionID {
                return ManagedLensEntry(
                    id: id,
                    displayName: "Translate with DeepL",
                    kind: .deepL
                )
            }
            guard let lens = store.lens(id: id), lens.id != ExplanationLens.localTranslateID else {
                return nil
            }
            return ManagedLensEntry(id: id, displayName: lens.displayName, kind: .prompt(lens))
        }
    }

    private var visibleEntries: [ManagedLensEntry] {
        managedEntries.filter { entry in
            guard store.inlineLensIDs.contains(entry.id) else { return false }
            if case .deepL = entry.kind {
                return translateSettings.isConfigured
            }
            return true
        }
    }

    var body: some View {
        SettingsPage {
            HStack(alignment: .center) {
                Text("Lenses")
                    .font(.headline)
                Spacer()
                if let saveFeedback {
                    HStack(spacing: LensSaveFeedback.iconToMessageSpacing) {
                        Image(systemName: LensSaveFeedback.iconName)
                        Text(saveFeedback.message)
                    }
                        .font(.body)
                        .foregroundStyle(.green)
                }
            }
            Text("Lenses decide how SeeThis responds. Use a built-in lens or create your own instructions.")
                .foregroundStyle(.secondary)
            Picker(
                "Default lens",
                selection: Binding(
                    get: { store.defaultLensID },
                    set: { store.setDefaultLens(id: $0) }
                )
            ) {
                Text("None").tag(String?.none)
                ForEach(visibleEntries) { entry in
                    Text(entry.displayName).tag(Optional(entry.id))
                }
            }

            Divider()

            Text("Your lenses")
                .font(.headline)
            HStack(spacing: LensEditorSaveNote.iconToMessageSpacing) {
                Image(systemName: LensEditorSaveNote.iconName)
                Text("You can enable up to \(LensStore.maximumInlineLenses) lenses for the overlay. There's no limit on how many you create.")
            }
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(managedEntries) { entry in
                lensRow(for: entry)
            }
            if store.hasRemovedBuiltInLenses {
                Button("Restore built-in presets") {
                    store.restoreBuiltInLenses()
                    onLensesSaved()
                }
                .hoverHighlight()
            }
            Button("Create custom lens") {
                editorDraft = LensEditorDraft()
            }
            .hoverHighlight()

            Divider()

            SettingsDisclosure("Translation settings") {
                VStack(alignment: .leading, spacing: 6) {
                    TranslateTargetLanguagePicker(
                        store: translateSettings,
                        onChange: onLensesSaved
                    )
                    Text("Used by Translate, Translate with DeepL, and custom lenses that include the target language variable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Overlay preview")
                .font(.headline)
            Text("Drag buttons to change the order they appear in the overlay.")
                .foregroundStyle(.secondary)
            lensOverlayPreview()
        }
        .confirmationDialog(
            "Delete this lens?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { lens in
            Button("Delete \"\(lens.displayName)\"", role: .destructive) {
                _ = store.removeLens(id: lens.id)
                expandedLensIDs.remove(lens.id)
                pendingDelete = nil
                onLensesSaved()
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { lens in
            Text("\"\(lens.displayName)\" will be removed. This can't be undone.")
        }
        .sheet(item: $editorDraft) { draft in
            LensEditorForm(
                draft: Binding(
                    get: { editorDraft ?? draft },
                    set: { editorDraft = $0 }
                ),
                isNameAvailable: { displayName, excludingID in
                    store.isLensNameAvailable(displayName, excludingID: excludingID)
                },
                onCancel: { editorDraft = nil },
                onSave: {
                    guard
                        let editorDraft,
                        !editorDraft.preference.isEmpty,
                        store.isLensNameAvailable(editorDraft.displayName, excludingID: editorDraft.lensID)
                    else {
                        return
                    }
                    if let lensID = editorDraft.lensID {
                        store.updateCustomLens(
                            id: lensID,
                            displayName: editorDraft.displayName,
                            preference: editorDraft.preference
                        )
                    } else {
                        store.addCustomLens(
                            displayName: editorDraft.displayName,
                            preference: editorDraft.preference
                        )
                    }
                    onLensesSaved()
                    saveFeedback = .saved
                    let feedbackToken = UUID()
                    saveFeedbackToken = feedbackToken
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: LensSaveFeedback.displayDurationNanoseconds)
                        guard saveFeedbackToken == feedbackToken else { return }
                        saveFeedback = nil
                    }
                    self.editorDraft = nil
                }
            )
        }
    }

    @ViewBuilder
    private func lensRow(for entry: ManagedLensEntry) -> some View {
        let isExpanded = expandedLensIDs.contains(entry.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.displayName)
                    .font(.body)
                if store.defaultLensID == entry.id {
                    DefaultLensBadge()
                }
                if case .deepL = entry.kind, !translateSettings.isConfigured {
                    Text("Setup required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Toggle(
                        "Show inline in overlay",
                        isOn: Binding(
                            get: { store.inlineLensIDs.contains(entry.id) },
                            set: { isEnabled in
                                switch entry.kind {
                                case .deepL:
                                    _ = translateSettings.setDeepLLensVisible(isEnabled)
                                case .prompt, .localTranslate:
                                    _ = store.setInlineLens(id: entry.id, isEnabled: isEnabled)
                                }
                                onLensesSaved()
                            }
                        )
                    )
                    .labelsHidden()
                    .help("Show inline in overlay")
                    .disabled(
                        (!store.inlineLensIDs.contains(entry.id)
                            && store.inlineLensIDs.count >= LensStore.maximumInlineLenses)
                            || (isDeepLEntry(entry) && !translateSettings.isConfigured)
                    )
                    switch entry.kind {
                    case .localTranslate:
                        promptDisclosureButton(for: entry, isExpanded: isExpanded)
                    case .deepL:
                        Button {
                            toggleExpanded(entry.id)
                        } label: {
                            HStack(spacing: 3) {
                                Text(isExpanded ? "Hide setup" : (translateSettings.isConfigured ? "Settings" : "Set up"))
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                    case let .prompt(lens):
                        Button {
                            toggleExpanded(entry.id)
                        } label: {
                            HStack(spacing: 3) {
                                Text(isExpanded ? "Hide prompt" : "Show prompt")
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                        if !lens.isBuiltIn {
                            Button("Edit") {
                                editorDraft = LensEditorDraft(lens: lens)
                            }
                            .hoverHighlight()
                        }
                        Button("Delete") {
                            pendingDelete = lens
                        }
                        .hoverHighlight()
                        .disabled(store.lenses.count <= 1)
                    }
                }
            }
            if isExpanded {
                switch entry.kind {
                case .localTranslate:
                    lensPromptDetails(for: ExplanationLens.localTranslateCatalogEntry)
                case .deepL:
                    TranslateSettingsView(
                        store: translateSettings,
                        onConfigurationChanged: onLensesSaved
                    )
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case let .prompt(lens):
                    lensPromptDetails(for: lens)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func promptDisclosureButton(
        for entry: ManagedLensEntry,
        isExpanded: Bool
    ) -> some View {
        Button {
            toggleExpanded(entry.id)
        } label: {
            HStack(spacing: 3) {
                Text(isExpanded ? "Hide prompt" : "Show prompt")
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    private func lensPromptDetails(for lens: ExplanationLens) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lens.readerVisibleInstruction)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copyPrompt(for: lens)
            } label: {
                Image(systemName: copyFeedbackLensID == lens.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copyFeedbackLensID == lens.id ? .green : .secondary)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .help("Copy prompt")
            .hoverHighlight()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func isDeepLEntry(_ entry: ManagedLensEntry) -> Bool {
        if case .deepL = entry.kind { return true }
        return false
    }

    private func toggleExpanded(_ id: String) {
        if expandedLensIDs.contains(id) {
            expandedLensIDs.remove(id)
        } else {
            expandedLensIDs.insert(id)
        }
    }

    @ViewBuilder
    private func lensOverlayPreview() -> some View {
        let inlineEntries = visibleEntries
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if inlineEntries.isEmpty {
                    Text("Enable at least one lens above to see it in the overlay.")
                        .foregroundStyle(.secondary)
                        .frame(width: OverlayPlacement.panelSize.width - 40, alignment: .leading)
                } else {
                    LensButtonFlow(
                        horizontalSpacing: OverlayLensListLayout.horizontalSpacing,
                        verticalSpacing: OverlayLensListLayout.verticalSpacing
                    ) {
                        ForEach(inlineEntries) { entry in
                            if draggingLensID == entry.id {
                                lensPreviewPlaceholder(for: entry)
                            } else {
                                lensPreviewButton(for: entry)
                            }
                        }
                    }
                    .frame(width: OverlayPlacement.panelSize.width - 40, alignment: .leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .onDrop(
                of: [UTType.plainText],
                delegate: LensContainerDropDelegate(draggingLensID: $draggingLensID)
            )
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func lensPreviewButton(for entry: ManagedLensEntry) -> some View {
        Text(entry.displayName)
            .font(.body)
            .padding(.horizontal, 11)
            .frame(height: OverlayLensListLayout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onDrag({
                draggingLensID = entry.id
                return NSItemProvider(object: entry.id as NSString)
            }, preview: {
                Color.clear.frame(width: 1, height: 1)
            })
            .onDrop(
                of: [UTType.plainText],
                delegate: LensRowDropDelegate(
                    targetLensID: entry.id,
                    draggingLensID: $draggingLensID,
                    store: store,
                    onMove: onLensesSaved
                )
            )
    }

    @ViewBuilder
    private func lensPreviewPlaceholder(for entry: ManagedLensEntry) -> some View {
        let width = OverlayLensListLayout.estimatedButtonWidth(for: entry.displayName)
        Text(entry.displayName)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(width: width, height: OverlayLensListLayout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.20))
            )
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.plainText],
                delegate: LensRowDropDelegate(
                    targetLensID: entry.id,
                    draggingLensID: $draggingLensID,
                    store: store,
                    onMove: onLensesSaved
                )
            )
            .transaction { $0.animation = nil }
    }

    private func copyPrompt(for lens: ExplanationLens) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lens.readerVisibleInstruction, forType: .string)
        let id = lens.id
        copyFeedbackLensID = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: LensSaveFeedback.displayDurationNanoseconds)
            if copyFeedbackLensID == id {
                copyFeedbackLensID = nil
            }
        }
    }
}

private struct ClampedTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let clamp: (String) -> String
    let onClamp: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClampedTextField
        init(_ parent: ClampedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let clamped = parent.clamp(field.stringValue)
            let wasClamped = clamped != field.stringValue
            if wasClamped {
                let editor = field.currentEditor()
                field.stringValue = clamped
                editor?.selectedRange = NSRange(location: clamped.count, length: 0)
            }
            if parent.text != clamped {
                parent.text = clamped
            }
            if wasClamped {
                parent.onClamp()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
    }
}

private struct LensEditorForm: View {
    @Binding var draft: LensEditorDraft
    let isNameAvailable: (String, String?) -> Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var showsLimitReached = false
    @State private var limitReachedResetToken: UUID?

    private var nameIsAvailable: Bool {
        isNameAvailable(draft.displayName, draft.lensID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.lensID == nil ? "Create custom lens" : "Edit custom lens")
                .font(.headline)
            ClampedTextField(
                placeholder: "Lens name",
                text: $draft.displayName,
                clamp: LensEditorDraft.clampDisplayName,
                onClamp: flashLimitReached
            )
                .frame(height: 20)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            if !draft.displayName.isEmpty && !nameIsAvailable {
                Text("A lens with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if showsLimitReached {
                Text(LensEditorDraft.displayNameLimitReachedMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(LensEditorDraft.displayNameCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("How should SeeThis respond?")
                    .font(.body.weight(.medium))
                Spacer()
                Button {
                    draft.preference = LensEditorDraft.insertingTargetLanguageVariable(
                        into: draft.preference
                    )
                } label: {
                    Label("Insert target language", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Insert {{target_language}} so this lens follows Translation settings.")
                .disabled(
                    draft.preference.contains(ExplanationLens.targetLanguageVariable)
                )
            }
            TextEditor(text: $draft.preference)
                .font(.body)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    // Known: placeholder briefly overlaps IME marked text (SwiftUI TextEditor's binding excludes it).
                    if draft.preference.isEmpty {
                        Text("e.g. Explain the selection in plain English.")
                            .font(.body)
                            .foregroundColor(Color(nsColor: .placeholderTextColor))
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.leading, 3)
                .padding(.trailing, 3)
                .padding(.vertical, 8)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack(spacing: LensEditorSaveNote.iconToMessageSpacing) {
                Image(systemName: LensEditorSaveNote.iconName)
                Text(LensEditorSaveNote.message)
            }
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel)
                    .hoverHighlight()
                Spacer()
                Button("Save", action: onSave)
                    .hoverHighlight()
                    .disabled(
                        !nameIsAvailable
                            || !draft.displayNameIsWithinLimit
                            || draft.preference.isEmpty
                    )
            }
        }
        .padding()
        .frame(minWidth: 420)
    }

    private func flashLimitReached() {
        showsLimitReached = true
        let token = UUID()
        limitReachedResetToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: LensEditorDraft.limitReachedFlashDurationNanoseconds)
            guard limitReachedResetToken == token else { return }
            showsLimitReached = false
        }
    }
}
