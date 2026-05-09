import Foundation

public struct DraftApproval: Equatable, Sendable {
    public var approvedByUser: Bool
    public var approvedAt: Date

    public init(approvedByUser: Bool, approvedAt: Date = Date()) {
        self.approvedByUser = approvedByUser
        self.approvedAt = approvedAt
    }
}

public enum DraftApprovalError: Error, Equatable, Sendable {
    case approvalRequired
}

public enum DraftApprovalConverter {
    public static func convert(
        _ draft: ProcessingDraft,
        categoryId: String,
        approval: DraftApproval?
    ) throws -> Todo {
        guard approval?.approvedByUser == true else {
            throw DraftApprovalError.approvalRequired
        }

        let now = approval?.approvedAt ?? Date()
        let todo = Todo(
            categoryId: categoryId,
            title: draft.title,
            summary: draft.summary,
            status: .open,
            dueDate: draft.dueDate,
            dueDateText: draft.dueDateText,
            scheduledDate: draft.scheduledDate,
            priority: draft.priority,
            createdAt: now,
            updatedAt: now
        )

        let blocks = draft.blocks
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.content < rhs.content
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, block in
                TodoBlock(
                    todoId: todo.id,
                    type: block.type,
                    content: block.content,
                    checked: block.checked,
                    order: index
                )
            }
        todo.blocks = blocks
        blocks.forEach { block in
            block.todo = todo
            block.todoId = todo.id
        }

        let reminders = draft.suggestedReminders
            .filter { reminder in
                reminder.defaultSelected && !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title < rhs.title
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, reminder in
                TodoReminder(
                    todoId: todo.id,
                    title: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    reminderDateText: reminder.reminderDateText?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty,
                    reminderDate: reminder.reminderDate,
                    reason: reminder.reason?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty,
                    isCompleted: false,
                    createdAt: now,
                    updatedAt: now,
                    order: index
                )
            }
        todo.reminders = reminders
        reminders.forEach { reminder in
            reminder.todo = todo
            reminder.todoId = todo.id
        }

        return todo
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        isEmpty ? nil : self
    }
}
