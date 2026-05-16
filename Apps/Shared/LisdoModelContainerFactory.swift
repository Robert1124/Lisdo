import Foundation
import LisdoCore
import SwiftData

public enum LisdoModelContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.com.yiwenwu.Lisdo"

    public static var schema: Schema {
        Schema([
            LisdoSyncedSettings.self,
            LisdoPendingRawCaptureAttachment.self,
            Category.self,
            CaptureItem.self,
            ProcessingDraft.self,
            Todo.self,
            TodoBlock.self,
            TodoReminder.self
        ])
    }

    public static func makeCloudKitContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LisdoCloud",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeLocalPersistentContainer(name: String = "LisdoLocal") throws -> ModelContainer {
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    public static func makeInMemoryPreviewContainer(seedDefaultCategories: Bool = true) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LisdoPreview",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])

        if seedDefaultCategories {
            try DefaultCategorySeeder.seedDefaults(in: container.mainContext)
        }

        return container
    }
}
