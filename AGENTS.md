# AGENTS.md

## Project Identity

Lisdo is a native Apple AI task inbox for iPhone and Mac. It is not a traditional todo app and it is not a website project. The core product loop is:

```text
capture -> extract text/OCR -> LLM draft -> user review -> category todo -> iCloud sync
```

All AI output must be draft-first. Never save LLM output as a final todo without an explicit user review/approval step in the product flow.

## Required Reading Order

Before planning or implementing, read these files:

1. `AI Task Inbox Bilingual Brief.md`
2. `docs/roadmap.md`
3. `docs/design.md`
4. `docs/architecture.md`

Use the app portions of `Design/Lisdo standalone.html` as the visual source of truth. Do not implement or document the website/landing/pricing sections from that prototype.

## Coordinator/Subagent Rule

The repository owner requires subagent-driven development.

The main process is a coordinator, not the primary coder. The main process should:

- read the docs and current project state;
- break work into concrete tasks with clear file ownership;
- dispatch implementation work to subagents;
- collect subagent results;
- review diffs against `docs/roadmap.md`, `docs/design.md`, and `docs/architecture.md`;
- resolve small integration conflicts;
- run builds/tests/checklists;
- update plans and report status.

The main process should not directly implement large features. Direct edits by the main process are allowed only for small documentation corrections, minor integration fixes after subagent work, verification scripts, or very small glue changes.

## Subagent Task Rules

Every implementation subagent must receive a bounded task with explicit ownership. Prefer disjoint write sets. Example slices:

- `LisdoCore` SwiftData models and status enums
- LLM provider abstraction and OpenAI-compatible BYOK provider
- strict draft JSON parser and validation tests
- Vision OCR adapter for iOS/macOS
- iPhone Inbox and Draft Review UI
- macOS sidebar/inbox/menu bar shell
- Widget and Live Activity shell targets
- Share Extension shell target
- XcodeGen/project scaffolding

Subagents must not revert work from other agents. If a file has active changes from another task, adapt to it or report the conflict.

Each subagent final response must include:

- files changed;
- acceptance criteria completed;
- validation commands run and results;
- remaining limitations or placeholders.

## Architecture Guardrails

- Minimum OS: iOS 17+, macOS 14+.
- UI: SwiftUI.
- Project generation: XcodeGen via `project.yml`.
- Shared core: an independent Swift Package named `LisdoCore`.
- Persistence/sync: SwiftData + CloudKit from MVP 1.
- Secrets: Keychain only. Do not sync API keys, CLI paths, OAuth tokens, or provider secrets through iCloud.
- OCR: Apple Vision adapters in platform layers.
- MVP 1 provider: OpenAI-compatible BYOK only, behind a provider abstraction.
- Future providers: Anthropic, Gemini, OpenRouter, CLI providers, Ollama, LM Studio/local models.
- Do not integrate Apple Reminders or Apple Calendar.
- Do not build a website in this repo during MVP 1.

## Design Guardrails

Follow `docs/design.md`.

The product must feel calm, monochrome, native, and work-oriented. Use pure white surfaces, near-black ink, restrained shadows, system typography, and draft-first visual treatment. Avoid marketing-style hero layouts, decorative gradients, purple/blue SaaS palettes, and playful todo-app decoration.

MVP 1 includes full product UI shell and real extension targets, but some capabilities are placeholders. Placeholder screens must look like intentional product states, not unfinished pages.

## Verification Expectations

For core logic, prefer unit tests. At minimum, verify:

- draft JSON parsing;
- invalid JSON and missing field handling;
- draft-to-todo conversion;
- category fallback behavior;
- capture/draft/todo status transitions.

For platform work, verify the relevant Xcode targets build. MVP 1 should build the iOS app, macOS app, Widget/Live Activity shell, Share Extension shell, and `LisdoCore` tests.

Do not claim a milestone is complete until verification has been run or the missing verification is explicitly reported.

