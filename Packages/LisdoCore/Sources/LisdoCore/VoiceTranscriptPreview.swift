import Foundation

public struct LisdoVoiceTranscriptPreview: Equatable, Sendable {
    public static let placeholderText = "Just say what's on your mind - Lisdo will turn it into a draft."

    public var text: String
    public var isPlaceholder: Bool

    public static func make(finalizedTranscript: String?) -> LisdoVoiceTranscriptPreview {
        if let finalizedTranscript = finalizedTranscript.trimmedNonEmpty {
            return LisdoVoiceTranscriptPreview(text: finalizedTranscript, isPlaceholder: false)
        }

        return LisdoVoiceTranscriptPreview(text: placeholderText, isPlaceholder: true)
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
