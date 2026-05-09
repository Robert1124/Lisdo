# Lisdo

[Chinese README](README.zh-CN.md)

Lisdo is a native Apple AI task inbox for iPhone and Mac. It turns messy captures into structured, reviewable task drafts before anything becomes a final todo.

Core loop:

```text
capture -> text/OCR extraction -> LLM draft -> user review -> category todo -> iCloud sync
```

AI output is draft-first by design. Lisdo should never save LLM output as a final todo without an explicit user review and approval step.

## Highlights

- Native iOS 17+ and macOS 14+ apps built with SwiftUI.
- Shared business logic in the independent `LisdoCore` Swift package.
- SwiftData + CloudKit persistence and sync from MVP 1.
- Apple Vision OCR adapters in the platform app layers.
- OpenAI-compatible BYOK provider behind a provider abstraction.
- API keys and provider secrets stored locally in Keychain only.
- Real Widget, Live Activity, Share Extension, and macOS menu bar shell targets.
- Static bilingual marketing/demo page in `Website/`.

## Repository Structure

```text
Apps/
  iOS/                iPhone app target
  macOS/              Mac app target
  Shared/             shared platform services
Extensions/
  Share/              iOS Share Extension shell
  Shared/             shared ActivityKit attributes
  Widgets/            Widget + Live Activity shell
Packages/
  LisdoCore/          shared Swift package and tests
Website/              static bilingual webpage/demo
docs/                 product, design, and architecture docs
Design/               app visual source and assets
project.yml           XcodeGen source of truth
```

## Requirements

- macOS with Xcode 15+.
- iOS 17+ / macOS 14+ deployment targets.
- Swift 5.9.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the Xcode project from `project.yml`.

## Getting Started

Generate the Xcode project:

```sh
xcodegen generate
```

Open the generated project:

```sh
open Lisdo.xcodeproj
```

Run core tests:

```sh
swift test --package-path Packages/LisdoCore
```

Serve the static webpage locally:

```sh
cd Website
python3 -m http.server 4173 --bind 127.0.0.1
```

Then open `http://127.0.0.1:4173/`. English is the default; use `?lang=zh` for the Chinese version.

## Product Guardrails

- Lisdo is not a traditional todo app and not a website-first project.
- All AI results must enter a draft review flow before becoming todos.
- Do not sync API keys, CLI paths, OAuth tokens, or provider secrets through iCloud.
- Do not integrate Apple Reminders or Apple Calendar for MVP 1.
- Default image handling should sync OCR text and metadata, not original images.

## Development Notes

- `project.yml` is the source of truth for Xcode targets.
- Generated `.xcodeproj` files and build products are ignored.
- `LisdoCore` owns shared models, draft parsing, provider contracts, fallback logic, draft-to-todo conversion, and testable state transitions.
- Platform targets own SwiftUI screens, Vision OCR adapters, Keychain implementation, model container wiring, and extension integration.

## License

Lisdo is open source under the MIT License. See [LICENSE](LICENSE).
