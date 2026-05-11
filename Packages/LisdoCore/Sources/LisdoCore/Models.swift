import Foundation
import SwiftData

public enum CaptureSourceType: String, Codable, CaseIterable, Sendable {
    case textPaste
    case clipboard
    case macScreenRegion
    case screenshotImport
    case photoImport
    case cameraImport
    case shareExtension
    case voiceNote
}

public enum CaptureStatus: String, Codable, CaseIterable, Sendable {
    case rawCaptured
    case pendingProcessing
    case processing
    case processedDraft
    case approvedTodo
    case failed
    case retryPending
}

public enum ProviderMode: String, Codable, CaseIterable, Sendable {
    case openAICompatibleBYOK
    case minimax
    case anthropic
    case gemini
    case openRouter
    case macOnlyCLI
    case ollama
    case lmStudio
    case localModel
}

public enum LisdoPendingRawCaptureAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case audio
}

public enum DeviceType: String, Codable, CaseIterable, Sendable {
    case iPhone
    case mac
    case unknown
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case open
    case inProgress
    case completed
    case archived
    case trashed
}

public enum TodoPriority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum TodoBlockType: String, Codable, CaseIterable, Sendable {
    case checkbox
    case bullet
    case note
}

public enum CategorySchemaPreset: String, Codable, CaseIterable, Sendable {
    case general
    case checklist
    case shoppingList
    case research
    case meeting
}

@Model
public final class LisdoSyncedSettings {
    public static let singletonId = "lisdo.synced-settings.singleton"
    public static let defaultImageProcessingModeRawValue = "vision-ocr"
    public static let defaultVoiceProcessingModeRawValue = "speech-transcript"
    public static let validImageProcessingModeRawValues = [
        "vision-ocr",
        "direct-llm"
    ]
    public static let validVoiceProcessingModeRawValues = [
        "speech-transcript"
    ]

    public var id: String = LisdoSyncedSettings.singletonId
    public var selectedProviderMode: ProviderMode = ProviderMode.openAICompatibleBYOK
    public var imageProcessingModeRawValue: String = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    public var voiceProcessingModeRawValue: String = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue
    public var updatedAt: Date = Date()

    public init(
        id: String = LisdoSyncedSettings.singletonId,
        selectedProviderMode: ProviderMode = .openAICompatibleBYOK,
        imageProcessingModeRawValue: String = LisdoSyncedSettings.defaultImageProcessingModeRawValue,
        voiceProcessingModeRawValue: String = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.selectedProviderMode = selectedProviderMode
        self.imageProcessingModeRawValue = imageProcessingModeRawValue
        self.voiceProcessingModeRawValue = voiceProcessingModeRawValue
        self.updatedAt = updatedAt
    }

    @discardableResult
    public func normalizeInvalidRawValues(updatedAt newUpdatedAt: Date = Date()) -> Bool {
        var didChange = false

        if !Self.validImageProcessingModeRawValues.contains(imageProcessingModeRawValue) {
            imageProcessingModeRawValue = Self.defaultImageProcessingModeRawValue
            didChange = true
        }

        if !Self.validVoiceProcessingModeRawValues.contains(voiceProcessingModeRawValue) {
            voiceProcessingModeRawValue = Self.defaultVoiceProcessingModeRawValue
            didChange = true
        }

        if didChange {
            updatedAt = newUpdatedAt
        }

        return didChange
    }

    public func updateProviderMode(_ mode: ProviderMode, updatedAt newUpdatedAt: Date = Date()) {
        selectedProviderMode = mode
        updatedAt = newUpdatedAt
    }

    public func updateImageProcessingModeRawValue(_ rawValue: String, updatedAt newUpdatedAt: Date = Date()) {
        imageProcessingModeRawValue = Self.normalizedImageProcessingModeRawValue(rawValue)
        updatedAt = newUpdatedAt
    }

    public func updateVoiceProcessingModeRawValue(_ rawValue: String, updatedAt newUpdatedAt: Date = Date()) {
        voiceProcessingModeRawValue = Self.normalizedVoiceProcessingModeRawValue(rawValue)
        updatedAt = newUpdatedAt
    }

    public static func normalizedImageProcessingModeRawValue(_ rawValue: String) -> String {
        validImageProcessingModeRawValues.contains(rawValue) ? rawValue : defaultImageProcessingModeRawValue
    }

    public static func normalizedVoiceProcessingModeRawValue(_ rawValue: String) -> String {
        validVoiceProcessingModeRawValues.contains(rawValue) ? rawValue : defaultVoiceProcessingModeRawValue
    }
}

@Model
public final class LisdoPendingRawCaptureAttachment {
    public var id: UUID = UUID()
    public var captureItemId: UUID?
    public var kind: LisdoPendingRawCaptureAttachmentKind = LisdoPendingRawCaptureAttachmentKind.image
    public var mimeOrFormat: String = ""
    public var filename: String?
    public var data: Data = Data()
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        captureItemId: UUID? = nil,
        kind: LisdoPendingRawCaptureAttachmentKind,
        mimeOrFormat: String,
        filename: String? = nil,
        data: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.captureItemId = captureItemId
        self.kind = kind
        self.mimeOrFormat = mimeOrFormat
        self.filename = filename
        self.data = data
        self.createdAt = createdAt
    }
}

@Model
public final class Category {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var descriptionText: String = ""
    public var formattingInstruction: String = ""
    public var schemaPreset: CategorySchemaPreset = CategorySchemaPreset.general
    public var icon: String?
    public var color: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: String = UUID().uuidString,
        name: String,
        descriptionText: String = "",
        formattingInstruction: String = "",
        schemaPreset: CategorySchemaPreset = .general,
        icon: String? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.formattingInstruction = formattingInstruction
        self.schemaPreset = schemaPreset
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class CaptureItem {
    public var id: UUID = UUID()
    public var sourceType: CaptureSourceType = CaptureSourceType.textPaste
    public var sourceText: String?
    public var sourceImageAssetId: String?
    public var sourceAudioAssetId: String?
    public var transcriptText: String?
    public var transcriptLanguage: String?
    public var userNote: String?
    public var createdDevice: DeviceType = DeviceType.unknown
    public var createdAt: Date = Date()
    public var status: CaptureStatus = CaptureStatus.rawCaptured
    public var preferredProviderMode: ProviderMode = ProviderMode.openAICompatibleBYOK
    public var assignedProcessorDeviceId: String?
    public var processingLockDeviceId: String?
    public var processingLockCreatedAt: Date?
    public var processingError: String?

    public init(
        id: UUID = UUID(),
        sourceType: CaptureSourceType,
        sourceText: String? = nil,
        sourceImageAssetId: String? = nil,
        sourceAudioAssetId: String? = nil,
        transcriptText: String? = nil,
        transcriptLanguage: String? = nil,
        userNote: String? = nil,
        createdDevice: DeviceType,
        createdAt: Date = Date(),
        status: CaptureStatus = .rawCaptured,
        preferredProviderMode: ProviderMode,
        assignedProcessorDeviceId: String? = nil,
        processingLockDeviceId: String? = nil,
        processingLockCreatedAt: Date? = nil,
        processingError: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceText = sourceText
        self.sourceImageAssetId = sourceImageAssetId
        self.sourceAudioAssetId = sourceAudioAssetId
        self.transcriptText = transcriptText
        self.transcriptLanguage = transcriptLanguage
        self.userNote = userNote
        self.createdDevice = createdDevice
        self.createdAt = createdAt
        self.status = status
        self.preferredProviderMode = preferredProviderMode
        self.assignedProcessorDeviceId = assignedProcessorDeviceId
        self.processingLockDeviceId = processingLockDeviceId
        self.processingLockCreatedAt = processingLockCreatedAt
        self.processingError = processingError
    }
}

public struct DraftBlock: Codable, Equatable, Hashable, Sendable {
    public var type: TodoBlockType
    public var content: String
    public var checked: Bool
    public var order: Int

    public init(type: TodoBlockType, content: String, checked: Bool = false, order: Int) {
        self.type = type
        self.content = content
        self.checked = checked
        self.order = order
    }
}

public struct DraftReminderSuggestion: Codable, Equatable, Hashable, Sendable {
    public var title: String
    public var reminderDateText: String?
    public var reminderDate: Date?
    public var reason: String?
    public var defaultSelected: Bool
    public var order: Int

    public init(
        title: String,
        reminderDateText: String? = nil,
        reminderDate: Date? = nil,
        reason: String? = nil,
        defaultSelected: Bool = true,
        order: Int
    ) {
        self.title = title
        self.reminderDateText = reminderDateText
        self.reminderDate = reminderDate
        self.reason = reason
        self.defaultSelected = defaultSelected
        self.order = order
    }
}

@Model
public final class ProcessingDraft {
    public var id: UUID = UUID()
    public var captureItemId: UUID = UUID()
    public var recommendedCategoryId: String?
    public var title: String = ""
    public var summary: String?
    public var blocks: [DraftBlock] = []
    public var suggestedReminders: [DraftReminderSuggestion] = []
    public var confidence: Double?
    public var generatedByProvider: String = ""
    public var generatedAt: Date = Date()
    public var needsClarification: Bool = false
    public var questionsForUser: [String] = []
    public var dueDateText: String?
    public var dueDate: Date?
    public var scheduledDate: Date?
    public var dateResolutionReferenceDate: Date?
    public var priority: TodoPriority?

    public init(
        id: UUID = UUID(),
        captureItemId: UUID,
        recommendedCategoryId: String? = nil,
        title: String,
        summary: String? = nil,
        blocks: [DraftBlock] = [],
        suggestedReminders: [DraftReminderSuggestion] = [],
        dueDateText: String? = nil,
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        dateResolutionReferenceDate: Date? = nil,
        priority: TodoPriority? = nil,
        confidence: Double? = nil,
        generatedByProvider: String = "",
        generatedAt: Date = Date(),
        needsClarification: Bool = false,
        questionsForUser: [String] = []
    ) {
        self.id = id
        self.captureItemId = captureItemId
        self.recommendedCategoryId = recommendedCategoryId
        self.title = title
        self.summary = summary
        self.blocks = blocks
        self.suggestedReminders = suggestedReminders
        self.dueDateText = dueDateText
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.dateResolutionReferenceDate = dateResolutionReferenceDate
        self.priority = priority
        self.confidence = confidence
        self.generatedByProvider = generatedByProvider
        self.generatedAt = generatedAt
        self.needsClarification = needsClarification
        self.questionsForUser = questionsForUser
    }
}

@Model
public final class Todo {
    public var id: UUID = UUID()
    public var categoryId: String = ""
    public var title: String = ""
    public var summary: String?
    public var status: TodoStatus = TodoStatus.open
    public var dueDate: Date?
    public var dueDateText: String?
    public var scheduledDate: Date?
    public var priority: TodoPriority?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \TodoBlock.todo)
    public var blocks: [TodoBlock]?
    @Relationship(deleteRule: .cascade, inverse: \TodoReminder.todo)
    public var reminders: [TodoReminder]?

    public init(
        id: UUID = UUID(),
        categoryId: String,
        title: String,
        summary: String? = nil,
        status: TodoStatus = .open,
        dueDate: Date? = nil,
        dueDateText: String? = nil,
        scheduledDate: Date? = nil,
        priority: TodoPriority? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        blocks: [TodoBlock] = [],
        reminders: [TodoReminder] = []
    ) {
        self.id = id
        self.categoryId = categoryId
        self.title = title
        self.summary = summary
        self.status = status
        self.dueDate = dueDate
        self.dueDateText = dueDateText
        self.scheduledDate = scheduledDate
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = blocks
        self.reminders = reminders
        blocks.forEach { block in
            block.todo = self
            block.todoId = id
        }
        reminders.forEach { reminder in
            reminder.todo = self
            reminder.todoId = id
        }
    }
}

@Model
public final class TodoBlock {
    public var id: UUID = UUID()
    public var todoId: UUID = UUID()
    public var todo: Todo?
    public var type: TodoBlockType = TodoBlockType.checkbox
    public var content: String = ""
    public var checked: Bool = false
    public var order: Int = 0

    public init(
        id: UUID = UUID(),
        todoId: UUID,
        todo: Todo? = nil,
        type: TodoBlockType,
        content: String,
        checked: Bool = false,
        order: Int
    ) {
        self.id = id
        self.todoId = todoId
        self.todo = todo
        self.type = type
        self.content = content
        self.checked = checked
        self.order = order
    }
}

@Model
public final class TodoReminder {
    public var id: UUID = UUID()
    public var todoId: UUID = UUID()
    public var todo: Todo?
    public var title: String = ""
    public var reminderDateText: String?
    public var reminderDate: Date?
    public var reason: String?
    public var isCompleted: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var order: Int = 0

    public init(
        id: UUID = UUID(),
        todoId: UUID,
        todo: Todo? = nil,
        title: String,
        reminderDateText: String? = nil,
        reminderDate: Date? = nil,
        reason: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        order: Int
    ) {
        self.id = id
        self.todoId = todoId
        self.todo = todo
        self.title = title
        self.reminderDateText = reminderDateText
        self.reminderDate = reminderDate
        self.reason = reason
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.order = order
    }
}
