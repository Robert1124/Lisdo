import Foundation
import LisdoCore
import SwiftData

public enum DefaultCategorySeeder {
    public struct CategoryTemplate: Equatable, Sendable {
        public var id: String
        public var name: String
        public var descriptionText: String
        public var formattingInstruction: String
        public var schemaPreset: CategorySchemaPreset
        public var icon: String?
        public var color: String?

        public init(
            id: String,
            name: String,
            descriptionText: String,
            formattingInstruction: String,
            schemaPreset: CategorySchemaPreset,
            icon: String? = nil,
            color: String? = nil
        ) {
            self.id = id
            self.name = name
            self.descriptionText = descriptionText
            self.formattingInstruction = formattingInstruction
            self.schemaPreset = schemaPreset
            self.icon = icon
            self.color = color
        }
    }

    public static let inboxCategoryId = "lisdo.default.inbox"

    public static let defaults: [CategoryTemplate] = [
        .init(
            id: inboxCategoryId,
            name: "Inbox",
            descriptionText: "Fallback category for drafts that need review before a final category is chosen.",
            formattingInstruction: "Preserve the user's source intent and ask for clarification when category confidence is low.",
            schemaPreset: .general,
            icon: "tray"
        )
    ]

    private static let legacyDefaultCategoryNamesById: [String: String] = [
        "lisdo.default.work": "Work",
        "lisdo.default.shopping": "Shopping",
        "lisdo.default.research": "Research",
        "lisdo.default.personal": "Personal",
        "lisdo.default.errands": "Errands"
    ]

    private static let legacySampleCaptureSource = "Revise the UCI questionnaire, send it to Yan, and confirm Zoom recording settings."
    private static let legacySampleDraftTitle = "Prepare UCI study group questionnaire"
    private static let legacySampleTodoTitle = "Review sample Lisdo draft"
    private static let legacySampleTodoSummary = "A sample item for preview containers only."

    @discardableResult
    public static func seedDefaults(in context: ModelContext) throws -> [Category] {
        try removeLegacyPlaceholderData(in: context)
        try reconcileDefaultCategories(in: context)

        let existingCategories = try context.fetch(FetchDescriptor<Category>())
        let existingIds = Set(existingCategories.map(\.id))
        let existingNames = Set(existingCategories.map { normalizedCategoryName($0.name) })

        var insertedCategories: [Category] = []
        for template in defaults where !existingIds.contains(template.id) && !existingNames.contains(normalizedCategoryName(template.name)) {
            let category = Category(
                id: template.id,
                name: template.name,
                descriptionText: template.descriptionText,
                formattingInstruction: template.formattingInstruction,
                schemaPreset: template.schemaPreset,
                icon: template.icon,
                color: template.color
            )
            context.insert(category)
            insertedCategories.append(category)
        }

        if context.hasChanges {
            try context.save()
        }

        return try context.fetch(FetchDescriptor<Category>())
    }

    private static func reconcileDefaultCategories(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<Category>())
        guard !categories.isEmpty else { return }

        let todos = try context.fetch(FetchDescriptor<Todo>())
        let drafts = try context.fetch(FetchDescriptor<ProcessingDraft>())

        for template in defaults {
            let candidates = categories.filter { category in
                category.id == template.id || normalizedCategoryName(category.name) == normalizedCategoryName(template.name)
            }

            guard let canonical = preferredDefaultCategory(
                from: candidates,
                template: template,
                todos: todos,
                drafts: drafts
            ) else {
                continue
            }

            let originalCanonicalId = canonical.id
            if canonical.id != template.id {
                canonical.id = template.id
            }
            applyMissingTemplateFields(template, to: canonical)

            let duplicateIds = Set(candidates.map(\.id)).union([originalCanonicalId])
            moveReferences(from: duplicateIds, to: template.id, todos: todos, drafts: drafts)

            for duplicate in candidates where duplicate !== canonical {
                context.delete(duplicate)
            }
        }
    }

    private static func preferredDefaultCategory(
        from candidates: [Category],
        template: CategoryTemplate,
        todos: [Todo],
        drafts: [ProcessingDraft]
    ) -> Category? {
        candidates.sorted { lhs, rhs in
            let lhsIsCanonical = lhs.id == template.id
            let rhsIsCanonical = rhs.id == template.id
            if lhsIsCanonical != rhsIsCanonical {
                return lhsIsCanonical
            }

            let lhsReferenceCount = referenceCount(for: lhs, todos: todos, drafts: drafts)
            let rhsReferenceCount = referenceCount(for: rhs, todos: todos, drafts: drafts)
            if lhsReferenceCount != rhsReferenceCount {
                return lhsReferenceCount > rhsReferenceCount
            }

            return lhs.createdAt < rhs.createdAt
        }
        .first
    }

    private static func referenceCount(for category: Category, todos: [Todo], drafts: [ProcessingDraft]) -> Int {
        todos.filter { $0.categoryId == category.id }.count
            + drafts.filter { $0.recommendedCategoryId == category.id }.count
    }

    private static func applyMissingTemplateFields(_ template: CategoryTemplate, to category: Category) {
        if category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            category.name = template.name
        }
        if category.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            category.descriptionText = template.descriptionText
        }
        if category.formattingInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            category.formattingInstruction = template.formattingInstruction
        }
        if category.icon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            category.icon = template.icon
        }
        if category.color?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            category.color = template.color
        }
    }

    private static func moveReferences(
        from categoryIds: Set<String>,
        to canonicalCategoryId: String,
        todos: [Todo],
        drafts: [ProcessingDraft]
    ) {
        for todo in todos where categoryIds.contains(todo.categoryId) && todo.categoryId != canonicalCategoryId {
            todo.categoryId = canonicalCategoryId
        }

        for draft in drafts {
            guard let recommendedCategoryId = draft.recommendedCategoryId,
                  categoryIds.contains(recommendedCategoryId),
                  recommendedCategoryId != canonicalCategoryId
            else {
                continue
            }

            draft.recommendedCategoryId = canonicalCategoryId
        }
    }

    private static func normalizedCategoryName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private static func removeLegacyPlaceholderData(in context: ModelContext) throws {
        let drafts = try context.fetch(FetchDescriptor<ProcessingDraft>())
        for draft in drafts where isLegacySampleDraft(draft) {
            context.delete(draft)
        }

        let todos = try context.fetch(FetchDescriptor<Todo>())
        for todo in todos where isLegacySampleTodo(todo) {
            context.delete(todo)
        }

        let captures = try context.fetch(FetchDescriptor<CaptureItem>())
        for capture in captures where isLegacySampleCapture(capture) {
            context.delete(capture)
        }

        let remainingTodoCategoryIds = Set(todos.filter { !isLegacySampleTodo($0) }.map(\.categoryId))
        let remainingDraftCategoryIds = Set(drafts.filter { !isLegacySampleDraft($0) }.compactMap(\.recommendedCategoryId))
        let referencedCategoryIds = remainingTodoCategoryIds.union(remainingDraftCategoryIds)

        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories where isLegacyPlaceholderCategory(category) && !referencedCategoryIds.contains(category.id) {
            context.delete(category)
        }
    }

    private static func isLegacySampleDraft(_ draft: ProcessingDraft) -> Bool {
        draft.generatedByProvider == "preview"
            || (draft.title == legacySampleDraftTitle && draft.recommendedCategoryId == "lisdo.default.work")
    }

    private static func isLegacySampleTodo(_ todo: Todo) -> Bool {
        todo.title == legacySampleTodoTitle
            && (todo.summary == legacySampleTodoSummary || todo.categoryId == inboxCategoryId)
    }

    private static func isLegacySampleCapture(_ capture: CaptureItem) -> Bool {
        capture.sourceText == legacySampleCaptureSource
            && capture.status == .processedDraft
            && capture.preferredProviderMode == .openAICompatibleBYOK
    }

    private static func isLegacyPlaceholderCategory(_ category: Category) -> Bool {
        guard let expectedName = legacyDefaultCategoryNamesById[category.id] else {
            return false
        }

        return category.name == expectedName
    }
}
