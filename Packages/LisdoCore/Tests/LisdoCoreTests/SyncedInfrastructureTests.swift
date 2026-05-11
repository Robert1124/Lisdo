import XCTest
@testable import LisdoCore

final class SyncedInfrastructureTests: XCTestCase {
    func testVoiceCapturePolicyLimitsRecordingsToOneMinute() {
        XCTAssertEqual(LisdoVoiceCapturePolicy.maximumDurationSeconds, 60)
    }

    func testQuickCaptureVoiceOrganizeCopyIsShortAction() {
        XCTAssertEqual(LisdoQuickCapturePresentationPolicy.voiceOrganizeTitle, "Organize")
    }

    func testQuickCaptureVoiceDismissesAfterStartingProcessing() {
        XCTAssertTrue(LisdoQuickCapturePresentationPolicy.dismissesVoiceAfterStartingProcessing)
    }

    func testVoiceTranscriptPreviewWaitsForFinalTranscript() {
        let preview = LisdoVoiceTranscriptPreview.make(finalizedTranscript: nil)

        XCTAssertEqual(preview.text, "Just say what's on your mind - Lisdo will turn it into a draft.")
        XCTAssertTrue(preview.isPlaceholder)
    }

    func testVoiceTranscriptPreviewUsesFinalTranscriptWhenReady() {
        let preview = LisdoVoiceTranscriptPreview.make(finalizedTranscript: "  Remind me to call mom about Sunday lunch  ")

        XCTAssertEqual(preview.text, "Remind me to call mom about Sunday lunch")
        XCTAssertFalse(preview.isPlaceholder)
    }

    func testSpeechLocalePolicyIncludesEnglishAndChineseCandidates() {
        let identifiers = LisdoSpeechLocalePolicy.candidateLocaleIdentifiers(primaryIdentifier: "fr_FR")

        XCTAssertEqual(identifiers.prefix(4), ["fr_FR", "en_US", "zh_CN", "zh_Hans"])
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testSpeechLocalePolicyPrefersChineseTranscriptWhenHanTextIsRecognized() {
        let candidate = LisdoSpeechLocalePolicy.bestCandidate(
            [
                .init(text: "show me shopping", languageCode: "en_US", confidence: 0.42),
                .init(text: "明天提醒我买菜", languageCode: "zh_CN", confidence: 0.36)
            ]
        )

        XCTAssertEqual(candidate?.languageCode, "zh_CN")
        XCTAssertEqual(candidate?.text, "明天提醒我买菜")
    }

    func testSpeechLocalePolicyPrefersEnglishTranscriptWhenLatinTextIsRecognized() {
        let candidate = LisdoSpeechLocalePolicy.bestCandidate(
            [
                .init(text: "开会", languageCode: "zh_CN", confidence: 0.31),
                .init(text: "Remind me to prepare the meeting notes", languageCode: "en_US", confidence: 0.46)
            ]
        )

        XCTAssertEqual(candidate?.languageCode, "en_US")
        XCTAssertEqual(candidate?.text, "Remind me to prepare the meeting notes")
    }

    func testSyncedSettingsDefaultsUseDraftFirstTextExtractionModes() {
        let settings = LisdoSyncedSettings(updatedAt: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(settings.id, LisdoSyncedSettings.singletonId)
        XCTAssertEqual(settings.selectedProviderMode, .openAICompatibleBYOK)
        XCTAssertEqual(settings.imageProcessingModeRawValue, LisdoSyncedSettings.defaultImageProcessingModeRawValue)
        XCTAssertEqual(settings.voiceProcessingModeRawValue, LisdoSyncedSettings.defaultVoiceProcessingModeRawValue)
        XCTAssertEqual(settings.imageProcessingModeRawValue, "vision-ocr")
        XCTAssertEqual(settings.voiceProcessingModeRawValue, "speech-transcript")
    }

    func testSyncedSettingsNormalizationRepairsInvalidRawValuesAndTouchesTimestamp() {
        let originalDate = Date(timeIntervalSince1970: 10)
        let normalizedDate = Date(timeIntervalSince1970: 30)
        let settings = LisdoSyncedSettings(
            imageProcessingModeRawValue: "raw-image-by-default",
            voiceProcessingModeRawValue: "raw-audio-by-default",
            updatedAt: originalDate
        )

        let didChange = settings.normalizeInvalidRawValues(updatedAt: normalizedDate)

        XCTAssertTrue(didChange)
        XCTAssertEqual(settings.imageProcessingModeRawValue, "vision-ocr")
        XCTAssertEqual(settings.voiceProcessingModeRawValue, "speech-transcript")
        XCTAssertEqual(settings.updatedAt, normalizedDate)
    }

    func testSyncedSettingsNormalizationKeepsDirectImageButForcesVoiceTranscriptMode() {
        let originalDate = Date(timeIntervalSince1970: 10)
        let normalizedDate = Date(timeIntervalSince1970: 30)
        let settings = LisdoSyncedSettings(
            imageProcessingModeRawValue: "direct-llm",
            voiceProcessingModeRawValue: "direct-llm",
            updatedAt: originalDate
        )

        let didChange = settings.normalizeInvalidRawValues(updatedAt: normalizedDate)

        XCTAssertTrue(didChange)
        XCTAssertEqual(settings.imageProcessingModeRawValue, "direct-llm")
        XCTAssertEqual(settings.voiceProcessingModeRawValue, "speech-transcript")
        XCTAssertEqual(settings.updatedAt, normalizedDate)
    }

    func testPendingRawCaptureAttachmentPreservesExplicitDirectMediaMetadata() {
        let id = UUID()
        let captureItemId = UUID()
        let createdAt = Date(timeIntervalSince1970: 50)
        let payload = Data([0x01, 0x02, 0x03])

        let attachment = LisdoPendingRawCaptureAttachment(
            id: id,
            captureItemId: captureItemId,
            kind: .image,
            mimeOrFormat: "image/png",
            filename: "screen-region.png",
            data: payload,
            createdAt: createdAt
        )

        XCTAssertEqual(attachment.id, id)
        XCTAssertEqual(attachment.captureItemId, captureItemId)
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.mimeOrFormat, "image/png")
        XCTAssertEqual(attachment.filename, "screen-region.png")
        XCTAssertEqual(attachment.data, payload)
        XCTAssertEqual(attachment.createdAt, createdAt)
    }

    func testPendingRawCaptureAttachmentAllowsUnlinkedAudioAttachmentMetadata() {
        let attachment = LisdoPendingRawCaptureAttachment(
            kind: .audio,
            mimeOrFormat: "audio/m4a",
            filename: nil,
            data: Data([0x0A])
        )

        XCTAssertNil(attachment.captureItemId)
        XCTAssertEqual(attachment.kind, .audio)
        XCTAssertEqual(attachment.mimeOrFormat, "audio/m4a")
    }
}
