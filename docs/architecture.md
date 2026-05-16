# Lisdo Architecture

## Overview

Lisdo is a native iPhone and Mac app with shared business logic in `LisdoCore`.

MVP 1 stack:

```text
SwiftUI
SwiftData + CloudKit
Apple Vision OCR
Keychain
OpenAI-compatible BYOK provider
XcodeGen
```

Minimum OS:

```text
iOS 17+
macOS 14+
```

## Proposed Repository Structure

The exact structure can be refined during implementation, but the architecture should follow this shape:

```text
AGENTS.md
project.yml
docs/
  roadmap.md
  design.md
  architecture.md
Packages/
  LisdoCore/
    Package.swift
    Sources/
      LisdoCore/
    Tests/
      LisdoCoreTests/
Apps/
  iOS/
  macOS/
Extensions/
  Widgets/
  Share/
  LiveActivity/  # ActivityKit source grouping; shipped through the Widget Extension target
```

`project.yml` is the source of truth for Xcode targets.

## Module Boundaries

### LisdoCore

`LisdoCore` owns:

- shared model definitions;
- status enums;
- draft JSON schema;
- draft parser and validation;
- provider protocols;
- OpenAI-compatible request/response DTOs that are platform-independent;
- draft-to-todo conversion;
- category recommendation fallback logic;
- testable state transitions.

`LisdoCore` must not own:

- SwiftUI app screens;
- platform permissions;
- Keychain implementation details;
- Vision framework calls;
- Share Extension UI;
- Widget UI;
- Live Activity UI.

### Platform Targets

iOS/macOS app targets own:

- SwiftUI screens;
- navigation;
- platform-specific OCR adapters;
- Keychain service implementation;
- SwiftData model container wiring;
- CloudKit entitlements/setup;
- importers/pickers;
- extension integration.

## Data Model

The brief's structs should be implemented as SwiftData model classes or equivalent persistent models. Implementation must respect SwiftData + CloudKit constraints.

Primary entities:

- `Category`
- `CaptureItem`
- `ProcessingDraft`
- `Todo`
- `TodoBlock`

### Category

Fields:

- `id`
- `name`
- `descriptionText`
- `formattingInstruction`
- `schemaPreset`
- `icon`
- `color`
- `createdAt`
- `updatedAt`

### CaptureItem

Fields:

- `id`
- `sourceType`
- `sourceText`
- `sourceImageAssetId`
- `sourceAudioAssetId`
- `transcriptText`
- `transcriptLanguage`
- `userNote`
- `createdDevice`
- `createdAt`
- `status`
- `preferredProviderMode`
- `assignedProcessorDeviceId`
- `processingLockDeviceId`
- `processingLockCreatedAt`
- `processingError`

MVP 1 usually stores text and OCR text. It should not sync original images by default.

### ProcessingDraft

Fields:

- `id`
- `captureItemId`
- `recommendedCategoryId`
- `title`
- `summary`
- `confidence`
- `generatedByProvider`
- `generatedAt`
- `needsClarification`
- `questionsForUser`
- relationship to draft blocks or serializable draft block payload.

### Todo

Fields:

- `id`
- `categoryId`
- `title`
- `summary`
- `status`
- `dueDate`
- `scheduledDate`
- `priority`
- `createdAt`
- `updatedAt`
- relationship to `TodoBlock`.

### TodoBlock

Fields:

- `id`
- `todoId`
- `type`
- `content`
- `checked`
- `order`

## Capture Status

Base state machine:

```text
rawCaptured
  -> pendingProcessing
  -> processing
  -> processedDraft
  -> approvedTodo
```

Failure path:

```text
processing
  -> failed
  -> retryPending
  -> processing
```

MVP 1 mainly uses direct processing on the current device. MVP 2 adds Mac-only pending queue behavior.

## AI Pipeline

MVP 1 pipeline:

```text
capture input
  -> extract source text
  -> OCR if image
  -> build LLM request with category rules
  -> call OpenAI-compatible BYOK provider
  -> parse strict JSON
  -> validate draft
  -> show review UI
  -> convert approved draft to todo
  -> sync
```

LLM output must be strict JSON. Free-form Markdown should be treated as invalid provider output unless a future repair step is explicitly implemented.

Expected draft JSON shape:

```json
{
  "recommendedCategoryId": "work",
  "confidence": 0.82,
  "title": "Prepare UCI Study Group questionnaire",
  "summary": "Revise the questionnaire, send it to Yan for review, and confirm Zoom recording settings.",
  "blocks": [
    {
      "type": "checkbox",
      "content": "Revise the questionnaire",
      "checked": false
    }
  ],
  "dueDateText": "tomorrow before 3 PM",
  "priority": "medium",
  "needsClarification": false,
  "questionsForUser": []
}
```

The parser should validate required fields and preserve clarification questions.

## Provider Architecture

Define a provider abstraction early:

```text
TaskDraftProvider
  -> generateDraft(input, categories, options)
```

MVP 1 implementation:

- OpenAI-compatible BYOK endpoint.

Future implementations:

- Anthropic;
- Gemini;
- OpenRouter;
- Codex CLI;
- Claude Code CLI;
- Gemini CLI;
- Ollama;
- LM Studio/local server;
- custom local model.

Secrets:

- API keys in Keychain only.
- CLI paths local only.
- Provider mode may sync.
- Provider credentials must not sync.

## OCR Architecture

Use a protocol boundary so `LisdoCore` does not depend directly on Vision:

```text
TextRecognitionService
  -> recognizeText(from image)
```

iOS and macOS platform targets implement this with Apple Vision `VNRecognizeTextRequest`.

MVP 1 default:

- OCR on the device where image capture/import happens.
- Sync OCR text and metadata.
- Do not sync original image by default.

## Sync Architecture

SwiftData + CloudKit remains part of the MVP 1 architecture, but storage mode is entitlement-selected at app startup.

Commercial sync rule for this milestone:

- Free and Starter Trial use a local persistent SwiftData container with CloudKit disabled.
- Paid monthly plans use the CloudKit-backed SwiftData container when available.
- If CloudKit setup fails for a paid monthly plan, the app may fall back to local persistence and must present that as a CloudKit fallback, not as the entitlement-local mode.
- Changing the plan rebuilds the root SwiftData `ModelContainer` at runtime so the app switches between local-only and iCloud-backed storage without a restart.

Synced:

- categories;
- capture items;
- processing drafts;
- todos;
- todo blocks;
- pending queue metadata.

Not synced:

- API keys;
- BYOK provider secrets, including OpenAI-compatible API keys;
- CLI paths;
- provider secrets;
- original images by default;
- audio files by default.

## Extension Architecture

MVP 1 must create real targets/configurations for:

- Widget Extension;
- Live Activity shell through ActivityKit/Widget Extension configuration;
- Share Extension;
- macOS menu bar/floating capture shell.

MVP 1 extension targets can use sample/static data or limited real data. They must build and present intentional placeholder states.

MVP 2/3 will wire these targets to real capture and task data.

## Security And Privacy

Captured text may be sent to the user's configured LLM provider when the user chooses to organize it into a draft. The UI must make BYOK provider setup clear.

BYOK secrets are local-only for this milestone. New API key saves use this-device Keychain items; legacy synchronizable Keychain reads may remain as a migration fallback, but new writes must not create iCloud-synchronizable keychain entries by default.

Do not:

- sync secrets through iCloud;
- log API keys;
- log full provider request bodies in production logs;
- upload original images by default;
- auto-process Mac-only pending items without user opt-in.

## Testing Strategy

`LisdoCore` tests are required first.

Minimum test coverage:

- valid draft JSON parsing;
- invalid JSON handling;
- missing required draft fields;
- clarification-question draft handling;
- category recommendation fallback;
- draft-to-todo conversion;
- capture status transitions;
- todo block ordering.

Platform verification:

- iOS app target builds;
- macOS app target builds;
- Widget target builds;
- Share Extension target builds;
- Live Activity shell builds where applicable;
- manual checklist for CloudKit sync.
