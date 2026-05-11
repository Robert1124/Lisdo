import Foundation

public struct LisdoSpeechTranscriptCandidate: Equatable, Sendable {
    public var text: String
    public var languageCode: String
    public var confidence: Double

    public init(text: String, languageCode: String, confidence: Double) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageCode = languageCode
        self.confidence = confidence
    }
}

public enum LisdoSpeechLocalePolicy {
    public static func candidateLocaleIdentifiers(primaryIdentifier: String?) -> [String] {
        var identifiers: [String] = []
        if let primaryIdentifier = primaryIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !primaryIdentifier.isEmpty {
            identifiers.append(primaryIdentifier)
        }
        identifiers.append(contentsOf: ["en_US", "zh_CN", "zh_Hans", "zh_TW"])

        var seen = Set<String>()
        identifiers = identifiers.filter { identifier in
            guard !seen.contains(identifier) else { return false }
            seen.insert(identifier)
            return true
        }

        return identifiers
    }

    public static func preferredLiveLocaleIdentifier(primaryIdentifier: String?) -> String {
        let candidates = candidateLocaleIdentifiers(primaryIdentifier: primaryIdentifier)
        if let primaryChinese = candidates.first(where: { identifier in
            Locale(identifier: identifier).language.languageCode?.identifier == "zh"
        }) {
            return primaryChinese
        }
        return "zh_CN"
    }

    public static func bestCandidate(_ candidates: [LisdoSpeechTranscriptCandidate]) -> LisdoSpeechTranscriptCandidate? {
        candidates
            .filter { !$0.text.isEmpty }
            .max { score($0) < score($1) }
    }

    private static func score(_ candidate: LisdoSpeechTranscriptCandidate) -> Double {
        let script = scriptCounts(in: candidate.text)
        let language = Locale(identifier: candidate.languageCode).language.languageCode?.identifier
        let characterScore = min(Double(candidate.text.count), 80) * 0.15
        let confidenceScore = min(max(candidate.confidence, 0), 1) * 100

        let languageScriptScore: Double
        if language == "zh", script.han > 0 {
            languageScriptScore = 30 + min(Double(script.han), 10) * 5
        } else if language == "en", script.latin >= script.han {
            languageScriptScore = 20 + min(Double(script.latin), 20) * 0.5
        } else if language == "zh" || language == "en" {
            languageScriptScore = 8
        } else {
            languageScriptScore = 0
        }

        return confidenceScore + languageScriptScore + characterScore
    }

    private static func scriptCounts(in text: String) -> (han: Int, latin: Int) {
        var han = 0
        var latin = 0

        for scalar in text.unicodeScalars {
            if scalar.isLisdoHanScalar {
                han += 1
            } else if scalar.isLisdoLatinScalar {
                latin += 1
            }
        }

        return (han, latin)
    }
}

private extension Unicode.Scalar {
    var isLisdoHanScalar: Bool {
        (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
            || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value)
            || (0x2B820...0x2CEAF).contains(value)
            || (0xF900...0xFAFF).contains(value)
    }

    var isLisdoLatinScalar: Bool {
        (0x0041...0x005A).contains(value)
            || (0x0061...0x007A).contains(value)
            || (0x00C0...0x024F).contains(value)
    }
}
