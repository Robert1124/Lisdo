import Foundation
import UIKit
import Vision

public final class VisionTextRecognitionService: TextRecognitionService, @unchecked Sendable {
    public init() {}

    public func recognizeText(from imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? [])
                .compactMap { observation -> RecognizedTextLine? in
                    guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty
                    else {
                        return nil
                    }
                    return RecognizedTextLine(text: text, boundingBox: observation.boundingBox)
                }
                .sortedForReadingOrder()
                .map(\.text)

            guard !lines.isEmpty else {
                throw TextRecognitionError.noTextFound
            }

            return lines.joined(separator: "\n")
        }.value
    }

    public func recognizeText(from image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
            throw TextRecognitionError.unreadableImage
        }
        return try await recognizeText(from: imageData)
    }
}

private struct RecognizedTextLine {
    var text: String
    var boundingBox: CGRect
}

private extension Array where Element == RecognizedTextLine {
    func sortedForReadingOrder() -> [RecognizedTextLine] {
        sorted { lhs, rhs in
            let rowTolerance = Swift.max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.6
            let yDelta = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(yDelta) > rowTolerance {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }
}
