import Foundation

public enum DraftParsingError: Error, Equatable, Sendable {
    case invalidJSON
    case missingRequiredField(String)
    case emptyRequiredField(String)
    case invalidBlockType(index: Int, type: String)
    case invalidBlockContent(index: Int)
    case invalidPriority(String)
    case invalidConfidence(Double)
    case invalidDate(field: String, value: String)
}

public enum TaskDraftParser {
    private static let isoFormatter = ISO8601DateFormatter()

    public static func parse(
        _ json: String,
        captureItemId: UUID,
        generatedByProvider: String,
        generatedAt: Date = Date()
    ) throws -> ProcessingDraft {
        guard let data = json.data(using: .utf8) else {
            throw DraftParsingError.invalidJSON
        }

        let rawDraft: RawDraft
        do {
            rawDraft = try JSONDecoder().decode(RawDraft.self, from: data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw DraftParsingError.missingRequiredField(key.stringValue)
        } catch let error as DraftParsingError {
            throw error
        } catch {
            throw DraftParsingError.invalidJSON
        }

        if let confidence = rawDraft.confidence, !(0...1).contains(confidence) {
            throw DraftParsingError.invalidConfidence(confidence)
        }

        let questionsForUser = rawDraft.questionsForUser.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let title: String
        let rawBlocks: [RawDraftBlock]
        if rawDraft.needsClarification {
            title = rawDraft.title?.trimmedNonEmpty ?? "Clarification needed"
            rawBlocks = rawDraft.blocks ?? []
        } else {
            guard let rawTitle = rawDraft.title else {
                throw DraftParsingError.missingRequiredField("title")
            }

            title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw DraftParsingError.emptyRequiredField("title")
            }

            guard let decodedBlocks = rawDraft.blocks else {
                throw DraftParsingError.missingRequiredField("blocks")
            }
            rawBlocks = decodedBlocks
        }

        let blocks = try rawBlocks.enumerated().map { index, rawBlock in
            guard let type = TodoBlockType(rawValue: rawBlock.type) else {
                throw DraftParsingError.invalidBlockType(index: index, type: rawBlock.type)
            }

            let content = rawBlock.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw DraftParsingError.invalidBlockContent(index: index)
            }

            return DraftBlock(
                type: type,
                content: content,
                checked: rawBlock.checked ?? false,
                order: index
            )
        }

        let suggestedReminders = try (rawDraft.suggestedReminders ?? []).enumerated().map { index, rawReminder in
            DraftReminderSuggestion(
                title: rawReminder.title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderDateText: rawReminder.reminderDateText?.trimmedNonEmpty,
                reminderDate: try parseOptionalISODate(rawReminder.reminderDateISO, field: "suggestedReminders[\(index)].reminderDateISO"),
                reason: rawReminder.reason?.trimmedNonEmpty,
                defaultSelected: rawReminder.defaultSelected ?? true,
                order: rawReminder.order ?? index
            )
        }
        let dueDate = try parseOptionalISODate(rawDraft.dueDateISO, field: "dueDateISO")
        let scheduledDate = try parseOptionalISODate(rawDraft.scheduledDateISO, field: "scheduledDateISO")
        let dateResolutionReferenceDate = try parseOptionalISODate(
            rawDraft.dateResolutionReferenceISO,
            field: "dateResolutionReferenceISO"
        )

        return ProcessingDraft(
            captureItemId: captureItemId,
            recommendedCategoryId: rawDraft.recommendedCategoryId?.trimmedNonEmpty,
            title: title,
            summary: rawDraft.summary?.trimmedNonEmpty,
            blocks: blocks,
            suggestedReminders: suggestedReminders,
            dueDateText: rawDraft.dueDateText?.trimmedNonEmpty,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            dateResolutionReferenceDate: dateResolutionReferenceDate,
            priority: rawDraft.priority,
            confidence: rawDraft.confidence,
            generatedByProvider: generatedByProvider,
            generatedAt: generatedAt,
            needsClarification: rawDraft.needsClarification,
            questionsForUser: questionsForUser
        )
    }

    private static func parseOptionalISODate(_ value: String?, field: String) throws -> Date? {
        guard let trimmed = value?.trimmedNonEmpty else { return nil }
        guard let date = isoFormatter.date(from: trimmed) else {
            throw DraftParsingError.invalidDate(field: field, value: trimmed)
        }
        return date
    }
}

public enum MiniMaxDraftParser {
    public static func parse(
        _ rawContent: String,
        captureItemId: UUID,
        generatedByProvider: String,
        generatedAt: Date = Date()
    ) throws -> ProcessingDraft {
        let sanitized = sanitize(rawContent)
        return try TaskDraftParser.parse(
            sanitized,
            captureItemId: captureItemId,
            generatedByProvider: generatedByProvider,
            generatedAt: generatedAt
        )
    }

    static func sanitize(_ content: String) -> String {
        let base = content.removingLeadingMiniMaxThinkBlock()
        return firstBalancedJSONObject(in: base) ?? base
    }

    private static func firstBalancedJSONObject(in content: String) -> String? {
        var depth = 0
        var startIndex: String.Index? = nil
        var inString = false
        var escaped = false
        var i = content.startIndex
        while i < content.endIndex {
            let ch = content[i]
            // Only track string/escape state once inside the JSON object.
            // Quotes in stray preamble text must not affect inString.
            if startIndex != nil {
                if escaped {
                    escaped = false
                    i = content.index(after: i)
                    continue
                }
                if ch == "\\" && inString {
                    escaped = true
                    i = content.index(after: i)
                    continue
                }
                if ch == "\"" {
                    inString = !inString
                    i = content.index(after: i)
                    continue
                }
            }
            if !inString {
                if ch == "{" {
                    if depth == 0 { startIndex = i }
                    depth += 1
                } else if ch == "}", startIndex != nil {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        return String(content[start...i])
                    }
                }
            }
            i = content.index(after: i)
        }
        return nil
    }
}

private struct RawDraft: Decodable {
    let recommendedCategoryId: String?
    let confidence: Double?
    let title: String?
    let summary: String?
    let blocks: [RawDraftBlock]?
    let suggestedReminders: [RawDraftReminder]?
    let dueDateText: String?
    let dueDateISO: String?
    let scheduledDateISO: String?
    let dateResolutionReferenceISO: String?
    let priority: TodoPriority?
    let needsClarification: Bool
    let questionsForUser: [String]

    private enum CodingKeys: String, CodingKey {
        case recommendedCategoryId
        case confidence
        case title
        case summary
        case blocks
        case suggestedReminders
        case dueDateText
        case dueDateISO
        case scheduledDateISO
        case dateResolutionReferenceISO
        case priority
        case needsClarification
        case questionsForUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendedCategoryId = try container.decodeIfPresent(String.self, forKey: .recommendedCategoryId)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        blocks = try container.decodeIfPresent([RawDraftBlock].self, forKey: .blocks)
        suggestedReminders = try container.decodeIfPresent([RawDraftReminder].self, forKey: .suggestedReminders)
        dueDateText = try container.decodeIfPresent(String.self, forKey: .dueDateText)
        dueDateISO = try container.decodeIfPresent(String.self, forKey: .dueDateISO)
        scheduledDateISO = try container.decodeIfPresent(String.self, forKey: .scheduledDateISO)
        dateResolutionReferenceISO = try container.decodeIfPresent(String.self, forKey: .dateResolutionReferenceISO)
        if let rawPriority = try container.decodeIfPresent(String.self, forKey: .priority) {
            guard let decodedPriority = TodoPriority(rawValue: rawPriority) else {
                throw DraftParsingError.invalidPriority(rawPriority)
            }
            priority = decodedPriority
        } else {
            priority = nil
        }
        needsClarification = try container.decode(Bool.self, forKey: .needsClarification)
        questionsForUser = try container.decode([String].self, forKey: .questionsForUser)
    }
}

private struct RawDraftBlock: Decodable {
    let type: String
    let content: String
    let checked: Bool?
}

private struct RawDraftReminder: Decodable {
    let title: String
    let reminderDateText: String?
    let reminderDateISO: String?
    let reason: String?
    let defaultSelected: Bool?
    let order: Int?
}

private extension String {
    func removingLeadingMiniMaxThinkBlock() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<think>"),
              let closeRange = trimmed.range(of: "</think>", options: .caseInsensitive)
        else {
            return self
        }

        return String(trimmed[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
