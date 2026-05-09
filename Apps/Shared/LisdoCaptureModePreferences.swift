import Foundation

public enum LisdoImageProcessingMode: String, CaseIterable, Identifiable, Sendable {
    case visionOCR = "vision-ocr"
    case directLLM = "direct-llm"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .visionOCR:
            return "Vision OCR"
        case .directLLM:
            return "Send image to LLM"
        }
    }

    public var detailText: String {
        switch self {
        case .visionOCR:
            return "Lisdo extracts text locally with Apple Vision, then sends text to the provider."
        case .directLLM:
            return "Lisdo sends the image attachment to the selected provider for direct reading."
        }
    }
}

public enum LisdoVoiceProcessingMode: String, CaseIterable, Identifiable, Sendable {
    case speechTranscript = "speech-transcript"
    case directLLM = "direct-llm"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .speechTranscript:
            return "Speech transcript"
        case .directLLM:
            return "Send audio to LLM"
        }
    }

    public var detailText: String {
        switch self {
        case .speechTranscript:
            return "Lisdo transcribes audio locally first, lets you review the transcript, then sends text to the provider."
        case .directLLM:
            return "Lisdo sends the audio attachment to the selected provider for direct transcription and task extraction."
        }
    }
}

public enum LisdoCaptureModePreferences {
    public static let imageProcessingModeKey = "lisdo.capture.image-processing-mode"
    public static let voiceProcessingModeKey = "lisdo.capture.voice-processing-mode"

    public static func imageProcessingMode(userDefaults: UserDefaults = .standard) -> LisdoImageProcessingMode {
        guard let rawValue = userDefaults.string(forKey: imageProcessingModeKey),
              let mode = LisdoImageProcessingMode(rawValue: rawValue)
        else {
            return .directLLM
        }
        return mode
    }

    public static func voiceProcessingMode(userDefaults: UserDefaults = .standard) -> LisdoVoiceProcessingMode {
        guard let rawValue = userDefaults.string(forKey: voiceProcessingModeKey),
              let mode = LisdoVoiceProcessingMode(rawValue: rawValue)
        else {
            return .directLLM
        }
        return mode
    }
}
