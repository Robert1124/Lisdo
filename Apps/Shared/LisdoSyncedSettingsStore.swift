import Foundation
import LisdoCore
import SwiftData

public final class LisdoSyncedSettingsStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func fetchOrCreateSettings(updatedAt now: Date = Date()) throws -> LisdoSyncedSettings {
        if let existing = try fetchAndReconcileSettings() {
            let didNormalize = existing.normalizeInvalidRawValues(updatedAt: now)
            if didNormalize, context.hasChanges {
                try context.save()
            }
            return existing
        }

        let settings = LisdoSyncedSettings(updatedAt: now)
        context.insert(settings)
        try context.save()
        return settings
    }

    @discardableResult
    public func updateProviderMode(_ mode: ProviderMode, updatedAt now: Date = Date()) throws -> LisdoSyncedSettings {
        let settings = try fetchOrCreateSettings(updatedAt: now)
        settings.updateProviderMode(mode, updatedAt: now)
        try context.save()
        return settings
    }

    @discardableResult
    public func updateImageProcessingModeRawValue(_ rawValue: String, updatedAt now: Date = Date()) throws -> LisdoSyncedSettings {
        let settings = try fetchOrCreateSettings(updatedAt: now)
        settings.updateImageProcessingModeRawValue(rawValue, updatedAt: now)
        try context.save()
        return settings
    }

    @discardableResult
    public func updateVoiceProcessingModeRawValue(_ rawValue: String, updatedAt now: Date = Date()) throws -> LisdoSyncedSettings {
        let settings = try fetchOrCreateSettings(updatedAt: now)
        settings.updateVoiceProcessingModeRawValue(rawValue, updatedAt: now)
        try context.save()
        return settings
    }

    private func fetchAndReconcileSettings() throws -> LisdoSyncedSettings? {
        let singletonId = LisdoSyncedSettings.singletonId
        let descriptor = FetchDescriptor<LisdoSyncedSettings>(
            predicate: #Predicate { settings in
                settings.id == singletonId
            },
            sortBy: [
                SortDescriptor(\LisdoSyncedSettings.updatedAt, order: .reverse)
            ]
        )
        let matches = try context.fetch(descriptor)
        guard let newest = matches.first else { return nil }

        for duplicate in matches.dropFirst() {
            context.delete(duplicate)
        }
        if context.hasChanges {
            try context.save()
        }

        return newest
    }
}
