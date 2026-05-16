# Lisdo Roadmap

## 产品定位

Lisdo 是一个跨 iPhone 和 Mac 的 AI task inbox。它的核心不是手动维护 todo list，而是把杂乱输入快速变成可审核、可编辑、可同步的结构化任务。

核心闭环：

```text
Capture -> Text/OCR extraction -> LLM draft -> User review -> Category todo -> iCloud sync
```

所有 AI 结果必须先进入 draft。用户确认后，draft 才能变成正式 todo。

## 已确认的基础决策

- 平台：iOS 17+ / macOS 14+。
- 技术：SwiftUI + SwiftData + CloudKit。
- 工程：XcodeGen 管理 `project.yml`。
- 共享核心：独立 Swift Package `LisdoCore`。
- MVP 1 provider：OpenAI-compatible BYOK。
- Provider 架构：预留 Anthropic、Gemini、OpenRouter、CLI、Ollama、LM Studio/local model。
- OCR：iOS/macOS 都使用 Apple Vision。
- 同步：MVP 1 保持 SwiftData + CloudKit 架构，但商业规则为 Free / Starter Trial 本机 local-only，付费 monthly plan 启用 iCloud。
- 图片策略：默认只同步 OCR text 和 metadata，不同步原图。
- 不做 Apple Reminders / Apple Calendar 集成。
- 不做 website/landing/pricing。
- MVP 1 要有完整产品 UI shell 和真实 extension targets，但部分功能可以是产品级 placeholder。

## MVP 1: Native Apple Foundation + Full UI Shell + Core Loop

### 目标

MVP 1 要建立 Lisdo 的原生 Apple 产品基座，并跑通最核心流程：

```text
Mac/iPhone app 内输入文本或导入图片
  -> 直接文本或 Vision OCR
  -> BYOK LLM 生成严格 JSON draft
  -> app 推荐 category
  -> 用户 review/edit
  -> 保存为 category todo
  -> CloudKit 双端同步
```

到 MVP 1，用户应该可以真实使用文本和图片 OCR 创建 AI draft，并把审核后的结果保存进不同 category。

### 真实可用功能

- iOS app target。
- macOS app target。
- `LisdoCore` Swift Package。
- XcodeGen `project.yml`。
- SwiftData model container；Free / Starter Trial 使用本机持久化，付费 monthly plan 使用 CloudKit。
- Category CRUD 的基础能力。
- Todo / TodoBlock 基础能力。
- CaptureItem / ProcessingDraft 基础状态。
- 文本输入和粘贴。
- 图片导入。
- Apple Vision OCR。
- OpenAI-compatible BYOK provider。
- API key 本机 Keychain 保存；本 milestone 不通过 iCloud Keychain 同步 BYOK 密钥。
- 严格 JSON draft parsing 和 validation。
- Draft review/edit/save。
- Category recommendation 和手动切换。
- Inbox View。
- Category View。
- iPhone 和 Mac 的完整主界面 shell。

### 真实 target，但功能先 placeholder

这些必须有真实 target 或真实入口，但 MVP 1 可以先显示产品级占位状态：

- Widget Extension。
- Live Activity / ActivityKit shell。
- Share Extension。
- macOS menu bar / floating capture shell。
- Voice capture UI。
- Plan / internal calendar UI。
- Pending from iPhone queue UI。
- Mac screen region capture UI entry。
- Global hotkey setting/entry。

Placeholder 必须像产品状态。例如：

- `Voice capture is coming in MVP 2`，同时展示录音入口和 transcript preview layout。
- `Waiting for Mac processing`，同时展示 pending item state。
- Widget 用 sample/static data，不留空白。

### MVP 1 不做

- Website / landing / pricing。
- Apple Reminders integration。
- Apple Calendar integration。
- 真正的 voice recording/transcription pipeline。
- 真正的 iOS Share Extension ingestion。
- 真正的 Mac screen-region capture。
- CLI provider execution。
- Ollama / LM Studio / local model execution。
- 多 provider fallback。

### MVP 1 成功标准

- iPhone app 和 Mac app 都能 build。
- Extension targets 能 build。
- 用户能在 iPhone 或 Mac app 内输入文本并生成 draft。
- 用户能导入图片并通过 Vision OCR 生成 draft。
- LLM 返回严格 JSON，app 能 parse/validate。
- 用户能审核、编辑、切换 category、保存 todo。
- 保存后的 todo 能按 category 展示。
- SwiftData model 从第一版开始按同步设计；iCloud 同步只在付费 monthly entitlement 下启用。
- Core parsing/status/conversion tests 通过。

## MVP 2: Capture Completion + Voice + Mac Pending Queue

### 目标

MVP 2 把系统级 capture 和 Mac-only processing 接成真实能力。到 MVP 2，用户应该可以通过 Share Sheet、voice、Mac menu bar、screen region 等方式进入同一条 draft pipeline。

### 功能

- Voice recording。
- Speech-to-text。
- Transcript review。
- Camera capture。
- iOS Share Extension 真实处理截图/文本/图片。
- Mac menu bar quick capture 真实处理。
- Global hotkey。
- Mac screen region capture。
- Vision OCR for screen region。
- Mac-only CLI provider abstraction。
- Codex CLI / Claude Code CLI / Gemini CLI 的基础适配策略。
- iPhone pending capture queue。
- CloudKit sync to Mac for pending captures。
- Mac `Process All`。
- Failed/retry states。
- Draft sync back to iPhone。

### MVP 2 成功标准

- iPhone Share Sheet capture 能进入 app。
- Voice 能生成 transcript，并能从 transcript 生成 draft。
- Mac menu bar capture 能生成 draft。
- Mac screen region 能 OCR 并进入 draft flow。
- CLI mode 下 iPhone capture 能 pending，Mac 能处理，draft 能回同步。

## MVP 3: System-Level Daily Experience

### 目标

MVP 3 把 MVP 1/2 中的 shell 和基础入口打磨成日常可用体验。

### 功能

- Interactive widgets。
- Widget refresh/data timeline。
- Active task Live Activity。
- Live Activity step progress。
- Share Extension UX polish。
- Menu bar UX polish。
- Notifications/status feedback。
- Basic Plan/calendar view 可用。
- Quick capture 的跨入口一致体验。

### MVP 3 成功标准

- Widget 不再只是 sample data，而能反映真实 today/draft/task 状态。
- Live Activity 能展示当前 active task step 和 next step。
- Plan view 能按 due/scheduled date 展示任务。
- 系统级入口体验稳定，不只是技术接线。

## MVP 4: Power User + Advanced AI Workflows

### 目标

MVP 4 面向重度用户和高级 AI 配置。

### 功能

- Anthropic provider。
- Gemini provider。
- OpenRouter provider。
- Ollama provider。
- LM Studio/local server provider。
- Local model mode。
- Provider fallback。
- Custom prompts per category。
- Custom schema/preset per category。
- Batch processing。
- Advanced internal planning。
- Advanced search/filter。
- Re-run draft with different instructions。
- More automation around capture cleanup and categorization.

### MVP 4 成功标准

- 用户可以按 category 定制整理规则。
- 用户可以配置多个 provider 和 fallback 策略。
- 本地模型和 API provider 都能进入统一 draft pipeline。
- 大量 capture item 能批量处理、重试、筛选和归档。

## 完整流程在哪个 MVP 跑通

基础完整流程在 **MVP 1** 跑通：

```text
Mac/iPhone app 内输入文本或导入图片
  -> LLM 转译/结构化
  -> app 识别并推荐 category
  -> 用户审核
  -> 添加进入不同 category
```

系统级完整流程在 **MVP 2** 跑通：

```text
Share Sheet / voice / menu bar / hotkey / screen region
  -> extraction/transcript/OCR
  -> LLM draft
  -> review
  -> category todo
```
