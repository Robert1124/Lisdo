import Foundation
import LisdoCore
import SwiftData

public final class LisdoPendingAttachmentStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func createExplicitMacCLIDirectAttachment(
        captureItemId: UUID?,
        kind: LisdoPendingRawCaptureAttachmentKind,
        mimeOrFormat: String,
        filename: String? = nil,
        data: Data,
        createdAt: Date = Date()
    ) throws -> LisdoPendingRawCaptureAttachment {
        let attachment = LisdoPendingRawCaptureAttachment(
            captureItemId: captureItemId,
            kind: kind,
            mimeOrFormat: mimeOrFormat,
            filename: filename,
            data: data,
            createdAt: createdAt
        )
        context.insert(attachment)
        try context.save()
        return attachment
    }

    public func fetchAttachments(forCaptureItemId captureItemId: UUID) throws -> [LisdoPendingRawCaptureAttachment] {
        let requestedCaptureItemId = captureItemId
        let descriptor = FetchDescriptor<LisdoPendingRawCaptureAttachment>(
            predicate: #Predicate { attachment in
                attachment.captureItemId == requestedCaptureItemId
            },
            sortBy: [
                SortDescriptor(\LisdoPendingRawCaptureAttachment.createdAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor)
    }

    public func fetchAttachment(id: UUID) throws -> LisdoPendingRawCaptureAttachment? {
        let requestedId = id
        var descriptor = FetchDescriptor<LisdoPendingRawCaptureAttachment>(
            predicate: #Predicate { attachment in
                attachment.id == requestedId
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func deleteAttachments(forCaptureItemId captureItemId: UUID) throws {
        let attachments = try fetchAttachments(forCaptureItemId: captureItemId)
        for attachment in attachments {
            context.delete(attachment)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    public func deleteAttachment(_ attachment: LisdoPendingRawCaptureAttachment) throws {
        context.delete(attachment)
        try context.save()
    }
}
