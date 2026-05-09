import LisdoCore
import SwiftData
import SwiftUI

struct DraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var captures: [CaptureItem]

    var draft: ProcessingDraft
    var categories: [Category]
    var sourceText: String
    var onSaved: () -> Void

    @State private var selectedCategoryId: String
    @State private var title: String
    @State private var summary: String
    @State private var dueDateText: String
    @State private var dateMode: LisdoIOSDraftDateMode
    @State private var selectedDate: Date
    @State private var blocks: [DraftBlock]
    @State private var suggestedReminders: [DraftReminderSuggestion]
    @State private var showSource = true
    @State private var saveError: String?
    @State private var revisionInstructions = ""
    @State private var isRevising = false

    init(draft: ProcessingDraft, categories: [Category], sourceText: String, onSaved: @escaping () -> Void) {
        self.draft = draft
        self.categories = categories
        self.sourceText = sourceText
        self.onSaved = onSaved
        _selectedCategoryId = State(initialValue: draft.recommendedCategoryId ?? categories.first?.id ?? "work")
        _title = State(initialValue: draft.title)
        _summary = State(initialValue: draft.summary ?? "")
        _dueDateText = State(initialValue: draft.dueDateText ?? "")
        if let scheduledDate = draft.scheduledDate {
            _dateMode = State(initialValue: .scheduled)
            _selectedDate = State(initialValue: scheduledDate)
        } else if let dueDate = draft.dueDate {
            _dateMode = State(initialValue: .due)
            _selectedDate = State(initialValue: dueDate)
        } else {
            _dateMode = State(initialValue: .none)
            _selectedDate = State(initialValue: Date())
        }
        _blocks = State(initialValue: draft.blocks.sorted { $0.order < $1.order })
        _suggestedReminders = State(initialValue: draft.suggestedReminders.sorted { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSection
                    categorySection
                    editorSection
                    reviseSection

                    if let saveError {
                        Text(saveError)
                            .font(.callout)
                            .foregroundStyle(LisdoTheme.warn)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 88)
            }
            .background(LisdoTheme.surface)
            .navigationTitle("Review draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    LisdoDraftChip()
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(sourceLabel, systemImage: sourceIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                Spacer()
                Button {
                    withAnimation(.snappy) { showSource.toggle() }
                } label: {
                    Image(systemName: showSource ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LisdoTheme.ink3)
            }

            if showSource {
                Text(sourceText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(LisdoTheme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(LisdoTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .lisdoCard()
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Suggested category", detail: confidenceText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.id) { category in
                        Button {
                            selectedCategoryId = category.id
                        } label: {
                            HStack(spacing: 6) {
                                LisdoCategoryDot(categoryId: category.id)
                                Text(category.name)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedCategoryId == category.id ? LisdoTheme.onAccent : LisdoTheme.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategoryId == category.id ? LisdoTheme.ink1 : LisdoTheme.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(LisdoTheme.divider, lineWidth: selectedCategoryId == category.id ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Draft details")

            VStack(alignment: .leading, spacing: 7) {
                Text("Title")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(LisdoTheme.ink3)
                TextField("Task title", text: $title, axis: .vertical)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .textFieldStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Summary")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(LisdoTheme.ink3)
                TextField("Optional summary", text: $summary, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Checklist")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(LisdoTheme.ink3)
                    Spacer()
                    Button {
                        blocks.append(DraftBlock(type: .checkbox, content: "", order: blocks.count))
                    } label: {
                        Label("Add step", systemImage: "plus")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink2)
                }

                ForEach(blocks.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(LisdoTheme.ink1.opacity(0.35))
                            .frame(width: 16, height: 16)
                        TextField("Checklist item", text: blockBinding(at: index), axis: .vertical)
                            .font(.system(size: 14))
                            .textFieldStyle(.plain)
                        Button {
                            blocks.remove(at: index)
                            reorderBlocks()
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(LisdoTheme.ink4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Suggested reminders")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(LisdoTheme.ink3)
                    Spacer()
                    Button {
                        suggestedReminders.append(DraftReminderSuggestion(title: "", order: suggestedReminders.count))
                    } label: {
                        Label("Add reminder", systemImage: "bell.badge")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink2)
                }

                if suggestedReminders.isEmpty {
                    Text("No reminder suggestions. Add one if this todo needs an advance reminder after review.")
                        .font(.system(size: 12))
                        .foregroundStyle(LisdoTheme.ink3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(suggestedReminders.indices, id: \.self) { index in
                        reminderRow(at: index)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Date")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(LisdoTheme.ink3)
                Picker("Date", selection: $dateMode) {
                    ForEach(LisdoIOSDraftDateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if dateMode != .none {
                    DatePicker(
                        dateMode == .due ? "Due date" : "Scheduled time",
                        selection: $selectedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }

                TextField("Original date phrase, optional", text: $dueDateText)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                Text("Use the picker for the saved date. The phrase is kept only as draft context.")
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
        .padding(16)
        .lisdoDashedDraft()
    }

    private var reviseSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle")
                Text("Revise with AI")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(LisdoTheme.ink2)

            Text("Revision updates this ProcessingDraft only. It still needs explicit review before it can become a todo.")
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)

            TextField("Make it shorter, add owner names, keep only the shopping items...", text: $revisionInstructions, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(2...5)
                .padding(12)
                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
                }
                .disabled(isRevising)

            Button {
                Task { await reviseDraft() }
            } label: {
                Label(isRevising ? "Revising..." : "Revise draft", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LisdoTheme.ink1)
            .disabled(isRevising || revisionInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard()
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("Keep editing") {}
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            Button {
                saveAsTodo()
            } label: {
                Label("Save as todo", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(LisdoTheme.ink1)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.thinMaterial)
    }

    private var sourceIcon: String {
        captures.first(where: { $0.id == draft.captureItemId }).map { capture in
            switch capture.sourceType {
            case .photoImport, .cameraImport, .screenshotImport:
                "photo"
            case .voiceNote:
                "mic"
            case .shareExtension:
                "square.and.arrow.down"
            case .clipboard:
                "doc.on.clipboard"
            case .macScreenRegion:
                "rectangle.dashed"
            case .textPaste:
                "text.alignleft"
            }
        } ?? "doc.text"
    }

    private var sourceLabel: String {
        captures.first(where: { $0.id == draft.captureItemId }).map { capture in
            switch capture.sourceType {
            case .textPaste: "Pasted text"
            case .clipboard: "Clipboard"
            case .photoImport: "Image import"
            case .cameraImport: "Camera"
            case .screenshotImport: "Screenshot"
            case .shareExtension: "Share extension"
            case .voiceNote: "Voice note"
            case .macScreenRegion: "Mac region"
            }
        } ?? "Captured source"
    }

    private var confidenceText: String? {
        draft.confidence.map { "\(Int($0 * 100))%" }
    }

    private func blockBinding(at index: Int) -> Binding<String> {
        Binding {
            blocks[index].content
        } set: { newValue in
            blocks[index].content = newValue
        }
    }

    private func reminderRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Button {
                    suggestedReminders[index].defaultSelected.toggle()
                } label: {
                    Image(systemName: suggestedReminders[index].defaultSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(suggestedReminders[index].defaultSelected ? LisdoTheme.ink1 : LisdoTheme.ink4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(suggestedReminders[index].defaultSelected ? "Reminder selected" : "Reminder not selected")

                TextField("Reminder title", text: reminderTitleBinding(at: index), axis: .vertical)
                    .font(.system(size: 14, weight: .medium))
                    .textFieldStyle(.plain)

                Button {
                    suggestedReminders.remove(at: index)
                    reorderReminders()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(LisdoTheme.ink4)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink4)
                    .frame(width: 16)
                TextField("Reminder time, e.g. the day before", text: reminderDateBinding(at: index), axis: .vertical)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink4)
                    .frame(width: 16)
                TextField("Why this reminder helps", text: reminderReasonBinding(at: index), axis: .vertical)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
            }
        }
        .padding(10)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
        }
    }

    private func reminderTitleBinding(at index: Int) -> Binding<String> {
        Binding {
            suggestedReminders[index].title
        } set: { newValue in
            suggestedReminders[index].title = newValue
        }
    }

    private func reminderDateBinding(at index: Int) -> Binding<String> {
        Binding {
            suggestedReminders[index].reminderDateText ?? ""
        } set: { newValue in
            suggestedReminders[index].reminderDateText = newValue
        }
    }

    private func reminderReasonBinding(at index: Int) -> Binding<String> {
        Binding {
            suggestedReminders[index].reason ?? ""
        } set: { newValue in
            suggestedReminders[index].reason = newValue
        }
    }

    private func reorderBlocks() {
        for index in blocks.indices {
            blocks[index].order = index
        }
    }

    private func reorderReminders() {
        for index in suggestedReminders.indices {
            suggestedReminders[index].order = index
        }
    }

    private func saveAsTodo() {
        saveError = nil
        reorderBlocks()
        reorderReminders()
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        syncDateEdits()
        draft.recommendedCategoryId = selectedCategoryId
        draft.blocks = blocks
            .map { block in
                var copy = block
                copy.content = copy.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
            .filter { !$0.content.isEmpty }
        draft.suggestedReminders = sanitizedReminders()

        do {
            let todo = try DraftApprovalConverter.convert(
                draft,
                categoryId: selectedCategoryId,
                approval: DraftApproval(approvedByUser: true)
            )
            modelContext.insert(todo)
            if let capture = captures.first(where: { $0.id == draft.captureItemId }) {
                if capture.status == .processedDraft {
                    try? capture.transition(to: .approvedTodo)
                } else {
                    capture.status = .approvedTodo
                }
            }
            modelContext.delete(draft)
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            onSaved()
            dismiss()
        } catch {
            saveError = "Could not save this draft as a todo. Review the title and category, then try again."
        }
    }

    @MainActor
    private func reviseDraft() async {
        let instructions = revisionInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else { return }

        saveError = nil
        isRevising = true
        defer { isRevising = false }

        do {
            guard let provider = try makeRevisionProvider() else {
                saveError = "No hosted API provider is configured. Add a local API key in You before revising this draft."
                return
            }

            let mode = revisionMode
            let settings = DraftProviderFactory().loadSettings(for: mode)
            let capture = captures.first(where: { $0.id == draft.captureItemId })
            let input = TaskDraftInput(
                captureItemId: draft.captureItemId,
                sourceText: revisionSourceText(capture: capture),
                userNote: capture?.userNote,
                preferredSchemaPreset: categories.first(where: { $0.id == selectedCategoryId })?.schemaPreset,
                revisionInstructions: instructions,
                captureCreatedAt: capture?.createdAt ?? draft.dateResolutionReferenceDate,
                timeZoneIdentifier: TimeZone.current.identifier
            )

            let revised = try await provider.generateDraft(
                input: input,
                categories: categories,
                options: TaskDraftProviderOptions(model: settings.model)
            )

            draft.recommendedCategoryId = revised.recommendedCategoryId ?? selectedCategoryId
            draft.title = revised.title
            draft.summary = revised.summary
            draft.blocks = revised.blocks.sorted { $0.order < $1.order }
            draft.suggestedReminders = revised.suggestedReminders.sorted { $0.order < $1.order }
            draft.dueDateText = revised.dueDateText
            draft.dueDate = revised.dueDate
            draft.scheduledDate = revised.scheduledDate
            draft.dateResolutionReferenceDate = revised.dateResolutionReferenceDate
            draft.priority = revised.priority
            draft.confidence = revised.confidence
            draft.generatedByProvider = revised.generatedByProvider
            draft.generatedAt = revised.generatedAt
            draft.needsClarification = revised.needsClarification
            draft.questionsForUser = revised.questionsForUser

            selectedCategoryId = draft.recommendedCategoryId ?? selectedCategoryId
            title = draft.title
            summary = draft.summary ?? ""
            dueDateText = draft.dueDateText ?? ""
            loadDateState(from: draft)
            blocks = draft.blocks.sorted { $0.order < $1.order }
            suggestedReminders = draft.suggestedReminders.sorted { $0.order < $1.order }
            revisionInstructions = ""
            try modelContext.save()
        } catch {
            saveError = "Draft revision failed: \(error.lisdoUserMessage)"
        }
    }

    private func makeRevisionProvider() throws -> (any TaskDraftProvider)? {
        let factory = DraftProviderFactory()
        return try factory.makeProvider(for: revisionMode)
    }

    private var revisionMode: ProviderMode {
        let preferred = captures.first(where: { $0.id == draft.captureItemId })?.preferredProviderMode ?? .openAICompatibleBYOK
        return hostedRevisionModes.contains(preferred) ? preferred : .openAICompatibleBYOK
    }

    private var hostedRevisionModes: [ProviderMode] {
        [.openAICompatibleBYOK, .minimax, .anthropic, .gemini, .openRouter]
    }

    private func revisionSourceText(capture: CaptureItem?) -> String {
        let original = capture?.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? capture?.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? sourceText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? draft.title

        let currentBlocks = blocks
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n- ")

        let currentReminders = suggestedReminders
            .map { reminder in
                let selected = reminder.defaultSelected ? "selected" : "not selected"
                return "\(reminder.title) (\(reminder.reminderDateText ?? "no time"), \(selected))"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n- ")

        return """
        Original capture:
        \(original)

        Current reviewed draft:
        Title: \(title)
        Summary: \(summary)
        Due text: \(dueDateText)
        Blocks:
        - \(currentBlocks)
        Suggested reminders:
        - \(currentReminders)
        """
    }

    private func syncDateEdits() {
        draft.dueDateText = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch dateMode {
        case .none:
            draft.dueDate = nil
            draft.scheduledDate = nil
        case .due:
            draft.dueDate = selectedDate
            draft.scheduledDate = nil
        case .scheduled:
            draft.dueDate = nil
            draft.scheduledDate = selectedDate
        }
    }

    private func loadDateState(from draft: ProcessingDraft) {
        dueDateText = draft.dueDateText ?? ""
        if let scheduledDate = draft.scheduledDate {
            dateMode = .scheduled
            selectedDate = scheduledDate
        } else if let dueDate = draft.dueDate {
            dateMode = .due
            selectedDate = dueDate
        } else {
            dateMode = .none
            selectedDate = Date()
        }
    }

    private func sanitizedReminders() -> [DraftReminderSuggestion] {
        suggestedReminders
            .map { reminder in
                DraftReminderSuggestion(
                    title: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    reminderDateText: reminder.reminderDateText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    reminderDate: reminder.reminderDate,
                    reason: reminder.reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    defaultSelected: reminder.defaultSelected,
                    order: reminder.order
                )
            }
            .filter { !$0.title.isEmpty }
    }
}

private extension Error {
    var lisdoUserMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return localizedDescription.isEmpty ? String(describing: self) : localizedDescription
    }
}

private enum LisdoIOSDraftDateMode: String, CaseIterable, Identifiable {
    case none
    case due
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "No date"
        case .due:
            return "Due"
        case .scheduled:
            return "Scheduled"
        }
    }
}
