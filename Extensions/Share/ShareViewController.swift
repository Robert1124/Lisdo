import Foundation
import LisdoCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let contentView = ShareIngestionView(extensionContext: extensionContext) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let hostingController = UIHostingController(rootView: contentView)

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private struct ShareIngestionView: View {
    @StateObject private var model: ShareIngestionViewModel
    let onDone: () -> Void

    init(extensionContext: NSExtensionContext?, onDone: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ShareIngestionViewModel(extensionContext: extensionContext))
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard

                if model.items.isEmpty, model.phase.showsEmptyState {
                    ShareMessageCard(
                        systemImage: model.phase.systemImage,
                        title: model.phase.cardTitle,
                        message: model.phase.cardMessage
                    )
                }

                if !model.items.isEmpty {
                    itemList
                }

                if let storageError = model.storageError {
                    ShareMessageCard(
                        systemImage: "exclamationmark.triangle",
                        title: "Storage needs attention",
                        message: storageError
                    )
                }

                doneButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .task {
            await model.startIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Share to Lisdo")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(model.phase.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)

            Text(model.phase.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ShareIconBox(systemImage: model.phase.systemImage)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.phase.cardTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.phase.cardMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if model.phase.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                ShareMetricPill(title: "Items", value: "\(model.totalItemCount)")
                ShareMetricPill(title: "Queued", value: "\(model.queuedCount)")
                ShareMetricPill(title: "Failed", value: "\(model.failedCount)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Captured items")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(model.items) { item in
                ShareItemRow(item: item)
            }
        }
    }

    private var doneButton: some View {
        VStack(spacing: 10) {
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.black.opacity(model.phase.isLoading ? 0.45 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(model.phase.isLoading)

            Text(model.phase.footerMessage)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

@MainActor
private final class ShareIngestionViewModel: ObservableObject {
    @Published private(set) var phase: ShareIngestionPhase = .loading
    @Published private(set) var items: [SharePersistedItem] = []
    @Published private(set) var totalItemCount: Int = 0
    @Published private(set) var storageError: String?

    private let extensionContext: NSExtensionContext?
    private var hasStarted = false
    private var modelContainer: ModelContainer?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    var queuedCount: Int {
        items.filter { $0.isQueued && $0.wasSaved }.count
    }

    var failedCount: Int {
        items.filter { !$0.isQueued || !$0.wasSaved }.count
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await ingestSharedContent()
    }

    private func ingestSharedContent() async {
        let providers = ShareInputCollector.providers(from: extensionContext)
        totalItemCount = providers.count

        guard !providers.isEmpty else {
            phase = .empty
            return
        }

        phase = .processing(count: providers.count)
        let extractedItems = await ShareAttachmentExtractor.extract(from: providers)
        totalItemCount = max(totalItemCount, extractedItems.count)

        guard !extractedItems.isEmpty else {
            phase = .failed(.unreadable)
            return
        }

        do {
            let container = try ShareExtensionModelContainerFactory.makeCloudKitContainer()
            modelContainer = container
            let context = container.mainContext

            for item in extractedItems {
                context.insert(item.capture)
            }

            try context.save()
            items = extractedItems.map { SharePersistedItem(output: $0) }

            if queuedCount > 0, failedCount > 0 {
                phase = .partial(queued: queuedCount, failed: failedCount)
            } else if queuedCount > 0 {
                phase = .success(queued: queuedCount)
            } else {
                phase = .failed(ShareFailureKind(outputs: extractedItems))
            }
        } catch {
            storageError = ShareIngestionError.storageUnavailable(error).message
            items = extractedItems.map { SharePersistedItem(output: $0, wasSaved: false) }
            phase = .storageFailed
        }
    }
}

private enum ShareExtensionModelContainerFactory {
    static let cloudKitContainerIdentifier = "iCloud.com.yiwenwu.Lisdo"

    static var schema: Schema {
        Schema([
            Category.self,
            CaptureItem.self,
            ProcessingDraft.self,
            Todo.self,
            TodoBlock.self
        ])
    }

    static func makeCloudKitContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LisdoCloud",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private enum ShareInputCollector {
    static func providers(from extensionContext: NSExtensionContext?) -> [NSItemProvider] {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return inputItems.flatMap { $0.attachments ?? [] }
    }
}

private enum ShareAttachmentExtractor {
    static func extract(from providers: [NSItemProvider]) async -> [ShareCaptureOutput] {
        var outputs: [ShareCaptureOutput] = []

        for (index, provider) in providers.enumerated() {
            outputs.append(await extract(from: provider, index: index))
        }

        return outputs
    }

    private static func extract(from provider: NSItemProvider, index: Int) async -> ShareCaptureOutput {
        do {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                return try await imageOutput(from: provider, index: index)
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                return try await urlOutput(from: provider, index: index)
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                return try await textOutput(from: provider, typeIdentifier: UTType.plainText.identifier, index: index)
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                return try await textOutput(from: provider, typeIdentifier: UTType.text.identifier, index: index)
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                return try await fileOutput(from: provider, index: index)
            }

            throw ShareIngestionError.unsupportedItem
        } catch let error as ShareIngestionError {
            return failedOutput(
                sourceType: fallbackSourceType(for: provider),
                title: fallbackTitle(for: provider, index: index),
                detail: error.message,
                error: error.message,
                failureKind: ShareFailureKind(error: error)
            )
        } catch {
            let ingestionError = ShareIngestionError.loadFailed(error)
            let message = ingestionError.message
            return failedOutput(
                sourceType: fallbackSourceType(for: provider),
                title: fallbackTitle(for: provider, index: index),
                detail: message,
                error: message,
                failureKind: ShareFailureKind(error: ingestionError)
            )
        }
    }

    private static func textOutput(from provider: NSItemProvider, typeIdentifier: String, index: Int) async throws -> ShareCaptureOutput {
        let item = try await provider.lisdoLoadItem(forTypeIdentifier: typeIdentifier)
        let text = try ShareLoadedItemParser.text(from: item)
        return queuedOutput(
            sourceType: .shareExtension,
            sourceText: text,
            title: provider.suggestedName?.nilIfBlank ?? "Shared text",
            detail: "Saved as pending capture input for the app or Mac provider pipeline."
        )
    }

    private static func urlOutput(from provider: NSItemProvider, index: Int) async throws -> ShareCaptureOutput {
        let item = try await provider.lisdoLoadItem(forTypeIdentifier: UTType.url.identifier)
        let text = try ShareLoadedItemParser.urlText(from: item)
        return queuedOutput(
            sourceType: .shareExtension,
            sourceText: text,
            title: provider.suggestedName?.nilIfBlank ?? "Shared link",
            detail: "Saved as pending capture input for the app or Mac provider pipeline."
        )
    }

    private static func imageOutput(from provider: NSItemProvider, index: Int) async throws -> ShareCaptureOutput {
        let imageData = try await ShareLoadedItemParser.imageData(from: provider)
        let ocrText = try await ShareVisionTextRecognizer.recognizeText(in: imageData)
        let sourceType: CaptureSourceType = provider.lisdoLooksLikeScreenshot ? .screenshotImport : .photoImport
        let title = provider.suggestedName?.nilIfBlank ?? (sourceType == .screenshotImport ? "Shared screenshot" : "Shared image")

        return queuedOutput(
            sourceType: sourceType,
            sourceText: ocrText,
            title: title,
            detail: "OCR text was saved as pending input for local or API draft processing."
        )
    }

    private static func fileOutput(from provider: NSItemProvider, index: Int) async throws -> ShareCaptureOutput {
        let item = try await provider.lisdoLoadItem(forTypeIdentifier: UTType.fileURL.identifier)
        let fileURL = try ShareLoadedItemParser.fileURL(from: item)
        let accessGranted = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType

        if contentType?.conforms(to: .image) == true || fileURL.lisdoLooksLikeImageFile {
            let ocrText = try await ShareVisionTextRecognizer.recognizeText(in: data)
            let sourceType: CaptureSourceType = fileURL.lisdoLooksLikeScreenshot ? .screenshotImport : .photoImport
            return queuedOutput(
                sourceType: sourceType,
                sourceText: ocrText,
                title: fileURL.lastPathComponent.nilIfBlank ?? "Shared image file",
                detail: "OCR text was saved as pending input for local or API draft processing."
            )
        }

        if contentType?.conforms(to: .text) == true || fileURL.lisdoLooksLikeTextFile {
            let text = try ShareLoadedItemParser.text(from: data)
            return queuedOutput(
                sourceType: .shareExtension,
                sourceText: text,
                title: fileURL.lastPathComponent.nilIfBlank ?? "Shared file",
                detail: "Saved as pending capture input for the app or Mac provider pipeline."
            )
        }

        throw ShareIngestionError.unsupportedFile
    }

    private static func queuedOutput(
        sourceType: CaptureSourceType,
        sourceText: String,
        title: String,
        detail: String
    ) -> ShareCaptureOutput {
        // The extension only persists capture input. Provider output must be reviewed in Lisdo before any Todo exists.
        ShareCaptureOutput(
            capture: CaptureItem(
                sourceType: sourceType,
                sourceText: sourceText,
                userNote: "Created by Lisdo Share Extension",
                createdDevice: .iPhone,
                status: .pendingProcessing,
                preferredProviderMode: .macOnlyCLI
            ),
            title: title,
            detail: detail,
            failureKind: nil,
            isQueued: true
        )
    }

    private static func failedOutput(
        sourceType: CaptureSourceType,
        title: String,
        detail: String,
        error: String,
        failureKind: ShareFailureKind
    ) -> ShareCaptureOutput {
        ShareCaptureOutput(
            capture: CaptureItem(
                sourceType: sourceType,
                userNote: "Created by Lisdo Share Extension",
                createdDevice: .iPhone,
                status: .failed,
                preferredProviderMode: .macOnlyCLI,
                processingError: error
            ),
            title: title,
            detail: detail,
            failureKind: failureKind,
            isQueued: false
        )
    }

    private static func fallbackSourceType(for provider: NSItemProvider) -> CaptureSourceType {
        if provider.lisdoLooksLikeScreenshot {
            return .screenshotImport
        }
        if provider.registeredTypeIdentifiers.contains(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) {
            return .photoImport
        }
        return .shareExtension
    }

    private static func fallbackTitle(for provider: NSItemProvider, index: Int) -> String {
        provider.suggestedName?.nilIfBlank ?? "Shared item \(index + 1)"
    }
}

private enum ShareLoadedItemParser {
    static func text(from item: Any) throws -> String {
        let rawText: String?

        if let text = item as? String {
            rawText = text
        } else if let text = item as? NSString {
            rawText = text as String
        } else if let attributedText = item as? NSAttributedString {
            rawText = attributedText.string
        } else if let data = item as? Data {
            rawText = String(data: data, encoding: .utf8)
        } else if let data = item as? NSData {
            rawText = String(data: data as Data, encoding: .utf8)
        } else {
            rawText = nil
        }

        guard let text = rawText?.nilIfBlank else {
            throw ShareIngestionError.emptyText
        }

        return text
    }

    static func urlText(from item: Any) throws -> String {
        let rawText: String?

        if let url = item as? URL {
            rawText = url.absoluteString
        } else if let url = item as? NSURL {
            rawText = url.absoluteString
        } else if let data = item as? Data {
            rawText = String(data: data, encoding: .utf8)
        } else if let text = item as? String {
            rawText = text
        } else if let text = item as? NSString {
            rawText = text as String
        } else {
            rawText = nil
        }

        guard let text = rawText?.nilIfBlank else {
            throw ShareIngestionError.emptyText
        }

        return text
    }

    static func fileURL(from item: Any) throws -> URL {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let data = item as? Data,
           let text = String(data: data, encoding: .utf8)?.nilIfBlank,
           let url = URL(string: text) {
            return url
        }

        if let text = item as? String,
           let url = URL(string: text) {
            return url
        }

        throw ShareIngestionError.fileUnavailable
    }

    static func imageData(from provider: NSItemProvider) async throws -> Data {
        do {
            let item = try await provider.lisdoLoadItem(forTypeIdentifier: UTType.image.identifier)

            if let data = try imageData(from: item) {
                return data
            }
        } catch {
            if let data = try? await provider.lisdoLoadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                return data
            }
            throw ShareIngestionError.loadFailed(error)
        }

        if let data = try? await provider.lisdoLoadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
            return data
        }

        throw ShareIngestionError.unreadableImage
    }

    private static func imageData(from item: Any) throws -> Data? {
        if let data = item as? Data {
            return data
        }

        if let data = item as? NSData {
            return data as Data
        }

        if let image = item as? UIImage {
            return image.pngData() ?? image.jpegData(compressionQuality: 0.92)
        }

        if let url = item as? URL {
            return try Data(contentsOf: url)
        }

        if let url = item as? NSURL {
            return try Data(contentsOf: url as URL)
        }

        return nil
    }
}

private enum ShareVisionTextRecognizer {
    static func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? [])
                .sorted { first, second in
                    if abs(first.boundingBox.midY - second.boundingBox.midY) > 0.02 {
                        return first.boundingBox.midY > second.boundingBox.midY
                    }
                    return first.boundingBox.minX < second.boundingBox.minX
                }
                .compactMap { observation in
                    observation.topCandidates(1).first?.string.nilIfBlank
                }

            guard !lines.isEmpty else {
                throw ShareIngestionError.noTextRecognized
            }

            return lines.joined(separator: "\n")
        }.value
    }
}

private struct ShareCaptureOutput {
    let capture: CaptureItem
    let title: String
    let detail: String
    let failureKind: ShareFailureKind?
    let isQueued: Bool

    var isFailed: Bool {
        !isQueued
    }
}

private struct SharePersistedItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let statusText: String
    let sourceTypeText: String
    let systemImage: String
    let isQueued: Bool
    let wasSaved: Bool

    init(output: ShareCaptureOutput, wasSaved: Bool = true) {
        id = output.capture.id
        title = output.title
        detail = wasSaved ? output.detail : "This item was read, but it was not saved. Open Lisdo once, then share again."
        isQueued = output.isQueued
        self.wasSaved = wasSaved
        statusText = Self.statusText(for: output, wasSaved: wasSaved)
        sourceTypeText = output.capture.sourceType.displayName
        systemImage = wasSaved ? output.rowSystemImage : "externaldrive.badge.exclamationmark"
    }

    private static func statusText(for output: ShareCaptureOutput, wasSaved: Bool) -> String {
        guard wasSaved else {
            return "Not saved"
        }

        if output.isQueued {
            return "Pending review"
        }

        return output.failureKind?.rowStatusText ?? "Needs review"
    }
}

private enum ShareIngestionPhase {
    case loading
    case processing(count: Int)
    case empty
    case success(queued: Int)
    case partial(queued: Int, failed: Int)
    case storageFailed
    case failed(ShareFailureKind)

    var title: String {
        switch self {
        case .loading:
            return "Preparing share"
        case .processing:
            return "Reading capture"
        case .empty:
            return "No content to capture"
        case .success:
            return "Capture queued"
        case .partial:
            return "Partially queued"
        case .storageFailed:
            return "Capture not saved"
        case .failed:
            return "Capture failed"
        }
    }

    var message: String {
        switch self {
        case .loading:
            return "Lisdo is opening the shared items."
        case let .processing(count):
            return "Extracting text from \(count) shared item\(count == 1 ? "" : "s")."
        case .empty:
            return "The share sheet did not provide text, a link, or an image for Lisdo to queue."
        case let .success(queued):
            return "\(queued) item\(queued == 1 ? "" : "s") saved for draft processing."
        case let .partial(queued, failed):
            return "\(queued) item\(queued == 1 ? "" : "s") queued for draft review. \(failed) item\(failed == 1 ? "" : "s") need attention."
        case .storageFailed:
            return "Lisdo read the shared content, but could not save it to the capture queue."
        case let .failed(kind):
            return kind.phaseMessage
        }
    }

    var cardTitle: String {
        switch self {
        case .loading:
            return "Opening shared content"
        case .processing:
            return "Extracting source text"
        case .empty:
            return "Nothing was received"
        case .success:
            return "Ready for draft processing"
        case .partial:
            return "Some content needs review"
        case .storageFailed:
            return "Storage needs attention"
        case .failed:
            return "Nothing was queued"
        }
    }

    var cardMessage: String {
        switch self {
        case .loading:
            return "This may take a moment for large files."
        case .processing:
            return "Lisdo saves only source text and OCR results here. A todo is never created from the share sheet."
        case .empty:
            return "Try sharing selected text, a link, a screenshot, or an image with readable text."
        case .success:
            return "Open Lisdo to run the selected API, Mac, or local-model provider and review the draft before saving any todo."
        case .partial:
            return "Queued captures remain draft-first for the app or Mac provider pipeline. Failed items include the reason below."
        case .storageFailed:
            return "No capture was saved. Open Lisdo once, confirm iCloud is available, then share again."
        case .failed:
            return "Open Lisdo and try sharing supported content with readable text."
        }
    }

    var footerMessage: String {
        switch self {
        case .loading:
            return "Keep this sheet open until the capture finishes."
        case .processing:
            return "Shared content is being converted into pending capture input."
        case .empty:
            return "No todo was created."
        case .success:
            return "No todo was created. Review is required in Lisdo."
        case .partial:
            return "No todo was created. Only queued items were saved for review."
        case .storageFailed:
            return "No content was saved. Nothing was created in Lisdo."
        case .failed:
            return "No content was saved as a todo."
        }
    }

    var systemImage: String {
        switch self {
        case .loading:
            return "tray.and.arrow.down"
        case .processing:
            return "text.viewfinder"
        case .empty:
            return "tray"
        case .success:
            return "checkmark.circle"
        case .partial:
            return "circle.lefthalf.filled"
        case .storageFailed:
            return "externaldrive.badge.exclamationmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        if case .processing = self {
            return true
        }
        return false
    }

    var showsEmptyState: Bool {
        switch self {
        case .empty, .failed, .storageFailed:
            return true
        case .loading, .processing, .success, .partial:
            return false
        }
    }
}

private struct ShareItemRow: View {
    let item: SharePersistedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareIconBox(systemImage: item.systemImage)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(item.statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isQueued && item.wasSaved ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Capsule())
                }

                Text(item.sourceTypeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
        }
    }
}

private struct ShareMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ShareMessageCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareIconBox(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ShareIconBox: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private enum ShareIngestionError: Error {
    case emptyText
    case noTextRecognized
    case unreadableImage
    case unsupportedItem
    case unsupportedFile
    case fileUnavailable
    case loadFailed(Error)
    case storageUnavailable(Error)

    var message: String {
        switch self {
        case .emptyText:
            return "This shared item did not contain readable text."
        case .noTextRecognized:
            return "No readable text was found in this image."
        case .unreadableImage:
            return "Lisdo could not read this image."
        case .unsupportedItem:
            return "This shared item type is not supported yet."
        case .unsupportedFile:
            return "This file is not a readable text or image file."
        case .fileUnavailable:
            return "Lisdo could not access this shared file."
        case let .loadFailed(error):
            return "Lisdo could not load this shared item. \(error.localizedDescription)"
        case let .storageUnavailable(error):
            return "Lisdo could not access iCloud storage from the share extension. Open Lisdo once, confirm iCloud is enabled, then share again. \(error.localizedDescription)"
        }
    }
}

private enum ShareFailureKind: Equatable {
    case empty
    case unsupported
    case ocrFailed
    case unreadable

    init(error: ShareIngestionError) {
        switch error {
        case .emptyText:
            self = .empty
        case .noTextRecognized, .unreadableImage:
            self = .ocrFailed
        case .unsupportedItem, .unsupportedFile:
            self = .unsupported
        case .fileUnavailable, .loadFailed, .storageUnavailable:
            self = .unreadable
        }
    }

    init(outputs: [ShareCaptureOutput]) {
        let failureKinds = outputs.compactMap(\.failureKind)
        if failureKinds.contains(.unsupported), failureKinds.allSatisfy({ $0 == .unsupported }) {
            self = .unsupported
        } else if failureKinds.contains(.ocrFailed), failureKinds.allSatisfy({ $0 == .ocrFailed }) {
            self = .ocrFailed
        } else if failureKinds.contains(.empty), failureKinds.allSatisfy({ $0 == .empty }) {
            self = .empty
        } else {
            self = .unreadable
        }
    }

    var rowStatusText: String {
        switch self {
        case .empty:
            return "Empty"
        case .unsupported:
            return "Unsupported"
        case .ocrFailed:
            return "OCR failed"
        case .unreadable:
            return "Unreadable"
        }
    }

    var phaseMessage: String {
        switch self {
        case .empty:
            return "The shared content did not contain readable text."
        case .unsupported:
            return "This share type is not supported yet."
        case .ocrFailed:
            return "Lisdo could not find readable text in the shared image."
        case .unreadable:
            return "Lisdo could not read this shared content."
        }
    }
}

private extension ShareCaptureOutput {
    var rowSystemImage: String {
        if isQueued {
            return capture.sourceType.systemImage
        }

        switch failureKind {
        case .empty:
            return "doc.text.magnifyingglass"
        case .unsupported:
            return "nosign"
        case .ocrFailed:
            return "text.viewfinder"
        case .unreadable, .none:
            return "exclamationmark.circle"
        }
    }
}

private extension NSItemProvider {
    func lisdoLoadItem(forTypeIdentifier typeIdentifier: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let item else {
                    continuation.resume(throwing: ShareIngestionError.unsupportedItem)
                    return
                }

                continuation.resume(returning: item)
            }
        }
    }

    func lisdoLoadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: ShareIngestionError.unreadableImage)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    var lisdoLooksLikeScreenshot: Bool {
        let searchableText = ([suggestedName ?? ""] + registeredTypeIdentifiers)
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains("screenshot") || searchableText.contains("screen shot")
    }
}

private extension URL {
    var lisdoLooksLikeImageFile: Bool {
        knownContentType?.conforms(to: .image) == true || ["png", "jpg", "jpeg", "heic", "heif", "tiff", "gif", "webp"].contains(pathExtension.lowercased())
    }

    var lisdoLooksLikeTextFile: Bool {
        knownContentType?.conforms(to: .text) == true || ["txt", "md", "markdown", "csv", "json", "rtf"].contains(pathExtension.lowercased())
    }

    var lisdoLooksLikeScreenshot: Bool {
        lastPathComponent.lowercased().contains("screenshot") || lastPathComponent.lowercased().contains("screen shot")
    }

    private var knownContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}

private extension CaptureSourceType {
    var displayName: String {
        switch self {
        case .textPaste, .clipboard, .shareExtension:
            return "Shared text"
        case .screenshotImport:
            return "Screenshot"
        case .photoImport, .cameraImport:
            return "Image"
        case .macScreenRegion:
            return "Screen capture"
        case .voiceNote:
            return "Voice note"
        }
    }

    var systemImage: String {
        switch self {
        case .textPaste, .clipboard, .shareExtension:
            return "doc.text"
        case .screenshotImport, .photoImport, .cameraImport:
            return "doc.viewfinder"
        case .macScreenRegion:
            return "rectangle.dashed"
        case .voiceNote:
            return "waveform"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
