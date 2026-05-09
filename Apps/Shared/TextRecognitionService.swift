import Foundation

public protocol TextRecognitionService: Sendable {
    func recognizeText(from imageData: Data) async throws -> String
}

public enum TextRecognitionError: Error, Equatable, Sendable {
    case unreadableImage
    case noTextFound
}
