# AI Task Inbox for Mac and iPhone — Product Brief / 产品需求文档

---

# 中文版本

## 1. 产品概述

这是一个面向 macOS 和 iPhone 的 AI 待办事项收集与整理应用。它不是传统意义上的 Todo App，而是一个 **AI Task Inbox / 智能任务收件箱**：用户可以通过复制粘贴、框选屏幕内容、截图、拍照、分享内容、语音输入等方式快速收集信息，然后由 LLM 自动判断任务类别、整理内容、生成摘要、拆分行动项，并在用户确认后保存为正式待办事项。

产品目标是减少用户从杂乱信息中手动整理任务的成本，让用户可以把任何信息快速丢进 App，由 AI 将其转换成结构化、可执行、可管理的任务。

核心定位：

> 一个跨 Mac 和 iPhone 的 AI capture inbox，用于把文本、截图、图片、语音和分享内容自动整理成结构化待办事项。

---

## 2. 核心使用场景

### 2.1 从文字中提取任务

用户复制一段聊天记录、邮件、网页内容、课程要求或工作需求，然后粘贴到 App 中。LLM 自动判断内容属于哪个 category，并整理成标题、摘要、bullet points 或 checklist。

### 2.2 从截图或屏幕区域中提取任务

Mac 端用户可以通过快捷键或 menu bar 图标进入类似截图工具的框选模式，选择屏幕上的一块区域。App 对截图内容进行 OCR，然后使用 LLM 提取和整理任务。

### 2.3 从 iPhone 截图或照片中提取任务

iPhone 用户可以截图后通过 Share Sheet 发送到 App，也可以直接拍照或导入图片。App 对图片进行 OCR，然后交给 LLM 整理成待办草稿。

### 2.4 从语音中快速创建任务

用户可以在 iPhone 或 Mac 上录制一段语音，例如：

> 明天下午三点前记得把 UCI study group 的 questionnaire 改完，然后发给 Yan 看一下，顺便确认 Zoom recording 的设置。

App 先进行语音转文字，再由 LLM 去口语化、提取行动项、判断 category，并生成可检查的 task draft。

### 2.5 iPhone 捕获，Mac 处理

如果用户选择的 LLM provider 是 Mac-only CLI，例如 Codex CLI、Claude Code CLI、Gemini CLI、Ollama 或 LM Studio，那么 iPhone 端不能直接生成 AI 内容。此时 iPhone 负责 capture，并通过 iCloud 将待处理事项同步给 Mac。Mac 下次打开 App 时检测 pending items，并调用 CLI provider 处理这些内容，再将生成的 draft 同步回 iPhone。

---

## 3. 功能需求

## 3.1 自定义 Category

用户可以创建不同的待办 category，并给每个 category 定义用途和格式规则。

示例：

### Work

定义：工作相关内容。整理需求时需要偏技术向、简洁、结构清晰。

输出格式：

- 简短标题
- 简介 / summary
- Bullet points
- 可选 due date
- 可选 priority

### Shopping List

定义：下次去超市或商店要购买的东西。

输出格式：

- 清单标题
- 商品 checklist
- 可选数量
- 可选备注

### Research

定义：论文、项目想法、实验设计、研究任务。

输出格式：

- 研究任务标题
- 背景摘要
- 待完成步骤
- 相关问题或假设

LLM 需要根据用户输入内容自动推荐最合适的 category。如果不确定，可以给出 confidence score 或询问用户确认。

---

## 3.2 AI Task Draft 生成流程

所有 AI 结果都应先进入 draft 状态，而不是直接保存为正式任务。

推荐流程：

```text
用户输入
  ↓
文本提取 / OCR / 语音转文字
  ↓
LLM 分类与结构化整理
  ↓
生成 Task Draft
  ↓
用户检查、编辑或和 LLM 对话调整
  ↓
用户确认
  ↓
保存为正式 Todo
```

Draft 内容包括：

- 推荐 category
- 标题
- 简短摘要
- bullet points / checklist / notes
- 可能的 due date
- 可能的 priority
- 需要用户确认的问题

用户可以在保存前进行：

- 手动编辑
- 更换 category
- 删除或添加 checklist item
- 与 LLM 聊天调整内容
- 放弃 draft

---

## 3.3 iCloud 双端同步

App 需要支持 Mac 和 iPhone 之间的数据同步。同步内容包括：

- Categories
- Capture Items
- Processing Drafts
- Todos
- Todo Blocks
- Pending Processing Queue

建议使用：

- SwiftData + CloudKit，或
- Core Data + CloudKit

App 不再需要与 Apple Reminders 或 Apple Calendar 联动。所有任务数据由 App 自己管理。

---

## 3.4 输入方式

App 需要支持以下 capture sources：

```text
- Text paste
- Clipboard capture
- Mac screen region capture
- Screenshot import
- Photo / camera import
- iOS Share Extension
- Voice note
```

### Mac 输入方式

Mac 端应支持：

- Menu bar quick capture
- Global hotkey
- Clipboard capture
- Paste text / image
- Screen region capture
- Voice capture
- OCR
- Draft review floating window

Mac 端的 screen region capture 逻辑：

```text
用户快捷键 / menu bar
  ↓
进入框选模式
  ↓
截取屏幕区域
  ↓
OCR 提取文字
  ↓
LLM 处理
  ↓
显示 draft review window
```

### iPhone 输入方式

iPhone 端应支持：

- Paste text
- Share Extension
- Screenshot share
- Photo import
- Camera capture
- Voice capture
- OCR
- Draft review

iPhone 端截图流程：

```text
用户截图
  ↓
Share Sheet
  ↓
发送到 App
  ↓
OCR / 文本提取
  ↓
BYOK 模式下直接 LLM 处理；CLI 模式下同步到 Mac
```

---

## 3.5 语音输入

语音输入是 App 的核心 capture source 之一。

推荐流程：

```text
用户录音
  ↓
Speech-to-text
  ↓
生成 raw transcript
  ↓
LLM 整理成 task draft
  ↓
用户检查 / 修改
  ↓
保存 Todo
```

语音转文字与 LLM 整理应分开处理。这样用户可以检查 transcript，也可以在不重新录音的情况下重新运行 LLM 整理。

### BYOK 模式

如果用户配置了 BYOK API provider，iPhone 和 Mac 都可以直接处理语音输入：

```text
录音 → 语音转文字 → LLM 整理 → Draft → 用户确认
```

### CLI 模式

如果用户使用 CLI provider：

```text
iPhone 录音
  ↓
iPhone 本机语音转文字
  ↓
创建 pending capture
  ↓
iCloud 同步到 Mac
  ↓
Mac 调用 CLI provider 整理
  ↓
Draft 同步回 iPhone
```

默认建议只同步 transcript，不同步完整音频文件。音频保存可以作为用户可选设置：

```text
- Save transcript only
- Save transcript + audio for 7 days
- Save transcript + audio permanently
```

默认值建议为：

```text
Save transcript only
```

---

## 3.6 LLM Provider 设计

LLM provider 分为两类：

### Cross-device Provider

这类 provider 可以在 Mac 和 iPhone 上直接调用。

示例：

- OpenAI API key
- Anthropic API key
- Gemini API key
- OpenRouter API key
- 用户自己的兼容 OpenAI API 的 endpoint

这类模式下，Mac 和 iPhone 都是全功能端。

流程：

```text
Capture on Mac/iPhone
  ↓
本机 OCR / transcript
  ↓
本机调用 API
  ↓
生成 draft
  ↓
用户确认
  ↓
iCloud 同步
```

### Mac-only Provider

这类 provider 只能在 Mac 上运行。

示例：

- Codex CLI
- Claude Code CLI
- Gemini CLI
- Ollama
- LM Studio local server
- 其他本地 CLI / local model

这类模式下，iPhone 不能直接生成 AI 内容。iPhone 只能 capture 并创建 pending item，等待 Mac 处理。

流程：

```text
iPhone capture
  ↓
创建 pending item
  ↓
iCloud 同步到 Mac
  ↓
Mac 打开 App
  ↓
调用 CLI provider
  ↓
生成 draft
  ↓
iCloud 同步回 iPhone
```

Provider 配置原则：

- API keys 不应通过 iCloud 同步
- CLI path 不应通过 iCloud 同步
- Provider credentials 应存在本机 Keychain
- 可以同步 provider mode，但不能同步 secrets

---

## 3.7 CLI Pending Queue

当用户使用 CLI provider 时，iPhone capture 的内容需要进入 pending queue。

状态机：

```text
rawCaptured
  ↓
pendingProcessing
  ↓
processingOnMac
  ↓
processedDraft
  ↓
approvedTodo
```

失败路径：

```text
pendingProcessing
  ↓
processingOnMac
  ↓
failed
  ↓
retryPending
```

Mac 打开 App 后应显示：

```text
You have 5 pending captures from iPhone.
[Process All]
```

建议不要默认自动调用 CLI，除非用户开启设置：

```text
Automatically process pending captures from iPhone
```

原因：

- CLI 可能消耗用户额度
- CLI 可能需要登录
- CLI 可能很慢
- CLI 输出可能失败
- 用户可能不希望一打开 App 就自动处理所有内容

更稳的默认行为：

```text
Mac menu bar badge: 5 pending captures
User clicks: Process All
```

---

## 3.8 任务查看方式

App 应至少支持三种主视图：

### Inbox View

显示所有刚 capture 或刚处理但尚未完全确认的内容。

### Category View

按用户自定义 category 查看正式 todos。

### Internal Calendar View

按照 due date 或 scheduled date 显示任务。注意：这是 App 内部的 calendar-style view，不需要同步到 Apple Calendar。

---

## 3.9 Widgets 与 Live Activity

### Widgets

Mac 和 iPhone 都需要支持不同尺寸的 widgets。

建议 widget 类型：

- Small：今日最重要任务
- Medium：当前 category 下的前几个任务
- Large：Today + Active Task + Quick Capture
- Interactive widget：勾选 checklist item、快速开始任务、快速 capture

### Live Activity

iPhone 端需要支持 Live Activity，用于显示用户正在执行的某个 task step。

示例：

```text
Todo: Prepare UCI class meeting
Current step: Draft questionnaire
Next step: Send to Yan for review
```

Live Activity 不适合展示所有普通待办，而适合展示当前正在进行的任务。

---

## 4. 数据模型建议

## 4.1 Category

```swift
struct Category {
    var id: UUID
    var name: String
    var description: String
    var formattingInstruction: String
    var schemaPreset: CategorySchemaPreset
    var icon: String?
    var color: String?
    var createdAt: Date
    var updatedAt: Date
}
```

## 4.2 CaptureItem

```swift
struct CaptureItem {
    var id: UUID
    var sourceType: CaptureSourceType
    var sourceText: String?
    var sourceImageAssetId: String?
    var sourceAudioAssetId: String?
    var transcriptText: String?
    var transcriptLanguage: String?
    var userNote: String?
    var createdDevice: DeviceType
    var createdAt: Date
    var status: CaptureStatus
    var preferredProviderMode: ProviderMode
    var assignedProcessorDeviceId: String?
    var processingLockDeviceId: String?
    var processingLockCreatedAt: Date?
    var processingError: String?
}
```

## 4.3 ProcessingDraft

```swift
struct ProcessingDraft {
    var id: UUID
    var captureItemId: UUID
    var recommendedCategoryId: UUID?
    var title: String
    var summary: String?
    var blocks: [TodoBlock]
    var confidence: Double?
    var generatedByProvider: String
    var generatedAt: Date
    var needsClarification: Bool
    var questionsForUser: [String]
}
```

## 4.4 Todo

```swift
struct Todo {
    var id: UUID
    var categoryId: UUID
    var title: String
    var summary: String?
    var blocks: [TodoBlock]
    var status: TodoStatus
    var dueDate: Date?
    var scheduledDate: Date?
    var priority: TodoPriority?
    var createdAt: Date
    var updatedAt: Date
}
```

## 4.5 TodoBlock

```swift
struct TodoBlock {
    var id: UUID
    var todoId: UUID
    var type: TodoBlockType
    var content: String
    var checked: Bool
    var order: Int
}
```

---

## 5. LLM 输出 Schema

LLM 应输出严格 JSON，避免自由 markdown 导致解析失败。

示例：

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
    },
    {
      "type": "checkbox",
      "content": "Send the revised questionnaire to Yan for review",
      "checked": false
    },
    {
      "type": "checkbox",
      "content": "Confirm Zoom recording settings",
      "checked": false
    }
  ],
  "dueDateText": "tomorrow before 3 PM",
  "priority": "medium",
  "needsClarification": false,
  "questionsForUser": []
}
```

如果 LLM 不确定，应返回：

```json
{
  "needsClarification": true,
  "questionsForUser": [
    "What time is tomorrow's meeting?"
  ]
}
```

---

## 6. 推荐 MVP 路线

## MVP 1: Core AI Task Inbox

目标：验证用户是否愿意把杂乱内容交给 AI 整理成任务。

功能：

- Mac + iPhone App
- iCloud sync
- 自定义 category
- 文本输入 / 粘贴
- 图片导入 + OCR
- BYOK provider
- LLM draft generation
- Draft review / edit
- Save as Todo
- Inbox View
- Category View

暂不做：

- CLI provider
- Live Activity
- Widgets
- Mac screen region capture
- iOS Share Extension
- Apple Reminders / Calendar integration

---

## MVP 2: Voice + CLI Pending Queue

功能：

- 语音输入
- Speech-to-text
- Transcript review
- CLI provider on Mac
- iPhone pending capture queue
- iCloud sync to Mac
- Mac process pending items
- Draft sync back to iPhone
- Retry / failed states

---

## MVP 3: System-level Capture

功能：

- Mac menu bar app
- Global hotkey
- Mac screen region capture
- iOS Share Extension
- Widgets
- Live Activity

---

## MVP 4: Advanced Power-user Features

功能：

- Local model provider
- Ollama / LM Studio integration
- Provider fallback
- Custom prompts per category
- Batch process pending captures
- Advanced calendar-style internal planning view

---

## 7. 关键产品判断

1. 这个产品不应该被定位为传统 Todo App，而应该定位为 AI capture inbox。
2. 所有 AI 结果都必须先作为 draft，由用户确认后再成为正式 todo。
3. BYOK 是双端全功能的基础路线。
4. CLI provider 应作为 Mac-only / power-user 功能。
5. iPhone 在 CLI 模式下不应直接调用 Mac CLI，而应通过 iCloud 创建 pending item，等待 Mac 处理。
6. 不接入 Apple Reminders / Calendar 是正确选择，可以显著降低复杂度。
7. 语音输入非常适合这个产品，因为它覆盖了“脑子里的任务”这一类 capture 场景。
8. 第一版应优先验证 capture → AI draft → user confirmation → todo 的核心闭环。

---

# English Version

## 1. Product Overview

This is an AI-powered task capture and organization app for macOS and iPhone. It is not a traditional Todo app. Instead, it should be positioned as an **AI Task Inbox**: users can quickly capture information through pasted text, clipboard content, selected screen regions, screenshots, photos, shared content, or voice notes. The app then uses an LLM to classify the content, recommend a category, summarize it, extract action items, and generate a structured task draft for user review.

The goal is to reduce the friction of manually turning messy information into actionable tasks.

Core positioning:

> A cross-device AI capture inbox for Mac and iPhone that turns text, screenshots, images, voice notes, and shared content into structured tasks.

---

## 2. Core Use Cases

### 2.1 Extract Tasks from Text

The user copies a chat message, email, webpage, course requirement, or work request and pastes it into the app. The LLM recommends a category and converts the content into a title, summary, bullet points, or checklist.

### 2.2 Extract Tasks from Screen Regions

On Mac, the user can trigger a screen-region capture using a global hotkey or the menu bar icon. The app captures the selected area, performs OCR, and sends the extracted text to the LLM for task structuring.

### 2.3 Extract Tasks from Screenshots or Photos on iPhone

On iPhone, the user can take a screenshot and share it to the app through the Share Sheet. The user can also import or take a photo directly in the app. The app performs OCR and then generates a structured task draft.

### 2.4 Create Tasks from Voice Notes

The user can record a quick voice note, such as:

> Before 3 PM tomorrow, remind me to revise the UCI Study Group questionnaire, send it to Yan for review, and confirm the Zoom recording settings.

The app first transcribes the audio, then uses the LLM to clean up the transcript, extract action items, recommend a category, and generate a task draft.

### 2.5 Capture on iPhone, Process on Mac

If the selected LLM provider is a Mac-only CLI provider, such as Codex CLI, Claude Code CLI, Gemini CLI, Ollama, or LM Studio, the iPhone cannot directly generate AI content. In this case, the iPhone acts as a capture device and syncs pending items to Mac through iCloud. The next time the Mac app is opened, it detects pending items, processes them using the CLI provider, and syncs the generated drafts back to iPhone.

---

## 3. Functional Requirements

## 3.1 Custom Categories

Users can create custom task categories, each with a description and formatting instructions.

Examples:

### Work

Definition: Work-related tasks. Requirements should be summarized in a concise, structured, technical style.

Output format:

- Short title
- Summary
- Bullet points
- Optional due date
- Optional priority

### Shopping List

Definition: Items to buy during the next shopping trip.

Output format:

- List title
- Product checklist
- Optional quantity
- Optional notes

### Research

Definition: Research tasks, paper notes, project ideas, experiment design, or study planning.

Output format:

- Research task title
- Background summary
- Action steps
- Open questions or hypotheses

The LLM should automatically recommend the most suitable category based on the captured input. If uncertain, it should provide a confidence score or ask the user for confirmation.

---

## 3.2 AI Task Draft Generation

AI-generated results should always enter a draft state first, rather than being saved directly as final tasks.

Recommended flow:

```text
User input
  ↓
Text extraction / OCR / speech-to-text
  ↓
LLM classification and structuring
  ↓
Generate Task Draft
  ↓
User reviews, edits, or revises through chat
  ↓
User approves
  ↓
Save as Todo
```

A draft should include:

- Recommended category
- Title
- Short summary
- Bullet points / checklist / notes
- Possible due date
- Possible priority
- Clarification questions if needed

Before saving, the user can:

- Manually edit the draft
- Change the category
- Add or remove checklist items
- Chat with the LLM to revise the draft
- Discard the draft

---

## 3.3 iCloud Sync

The app should support data sync between Mac and iPhone through iCloud.

Synced data includes:

- Categories
- Capture Items
- Processing Drafts
- Todos
- Todo Blocks
- Pending Processing Queue

Recommended implementation:

- SwiftData + CloudKit, or
- Core Data + CloudKit

The app will not integrate with Apple Reminders or Apple Calendar. All task data will be managed internally by the app.

---

## 3.4 Capture Sources

The app should support the following capture sources:

```text
- Text paste
- Clipboard capture
- Mac screen region capture
- Screenshot import
- Photo / camera import
- iOS Share Extension
- Voice note
```

### Mac Capture Methods

The Mac app should support:

- Menu bar quick capture
- Global hotkey
- Clipboard capture
- Text / image paste
- Screen region capture
- Voice capture
- OCR
- Floating draft review window

Mac screen-region capture flow:

```text
User triggers hotkey / menu bar action
  ↓
Enter region selection mode
  ↓
Capture selected screen area
  ↓
Run OCR
  ↓
Send extracted text to LLM
  ↓
Show draft review window
```

### iPhone Capture Methods

The iPhone app should support:

- Text paste
- Share Extension
- Screenshot sharing
- Photo import
- Camera capture
- Voice capture
- OCR
- Draft review

iPhone screenshot flow:

```text
User takes screenshot
  ↓
Share Sheet
  ↓
Send to app
  ↓
OCR / text extraction
  ↓
If BYOK mode: process locally through API
If CLI mode: sync to Mac for processing
```

---

## 3.5 Voice Input

Voice input should be a first-class capture source.

Recommended flow:

```text
User records audio
  ↓
Speech-to-text
  ↓
Generate raw transcript
  ↓
LLM converts transcript into task draft
  ↓
User reviews / edits
  ↓
Save Todo
```

Speech-to-text and LLM structuring should be separated. This allows the user to review the transcript and rerun the LLM step without recording audio again.

### BYOK Mode

If the user configures a BYOK API provider, both Mac and iPhone can process voice input directly:

```text
Record audio → Transcribe → LLM structuring → Draft → User approval
```

### CLI Mode

If the user uses a CLI provider:

```text
iPhone records audio
  ↓
iPhone performs speech-to-text locally
  ↓
Creates pending capture
  ↓
iCloud syncs it to Mac
  ↓
Mac processes it using CLI provider
  ↓
Draft syncs back to iPhone
```

By default, the app should sync only the transcript, not the full audio file. Audio storage can be offered as a user setting:

```text
- Save transcript only
- Save transcript + audio for 7 days
- Save transcript + audio permanently
```

Recommended default:

```text
Save transcript only
```

---

## 3.6 LLM Provider Design

LLM providers should be divided into two categories.

### Cross-device Providers

These providers can be called directly on both Mac and iPhone.

Examples:

- OpenAI API key
- Anthropic API key
- Gemini API key
- OpenRouter API key
- User-defined OpenAI-compatible endpoint

In this mode, both Mac and iPhone are fully functional processing clients.

Flow:

```text
Capture on Mac/iPhone
  ↓
Local OCR / transcript
  ↓
Call API directly
  ↓
Generate draft
  ↓
User approves
  ↓
iCloud sync
```

### Mac-only Providers

These providers can only run on Mac.

Examples:

- Codex CLI
- Claude Code CLI
- Gemini CLI
- Ollama
- LM Studio local server
- Other local CLI or local model providers

In this mode, the iPhone cannot directly generate AI content. It only captures input and creates pending items for Mac processing.

Flow:

```text
iPhone capture
  ↓
Create pending item
  ↓
iCloud syncs to Mac
  ↓
Mac app opens
  ↓
Mac calls CLI provider
  ↓
Draft is generated
  ↓
iCloud syncs draft back to iPhone
```

Provider configuration rules:

- API keys should not be synced through iCloud
- CLI paths should not be synced through iCloud
- Provider credentials should be stored locally in Keychain
- Provider mode can be synced, but secrets must remain device-local

---

## 3.7 CLI Pending Queue

When the user selects a CLI provider, iPhone captures should enter a pending queue.

State machine:

```text
rawCaptured
  ↓
pendingProcessing
  ↓
processingOnMac
  ↓
processedDraft
  ↓
approvedTodo
```

Failure path:

```text
pendingProcessing
  ↓
processingOnMac
  ↓
failed
  ↓
retryPending
```

When the Mac app opens, it should show:

```text
You have 5 pending captures from iPhone.
[Process All]
```

The app should not automatically run CLI processing by default unless the user enables:

```text
Automatically process pending captures from iPhone
```

Reasons:

- CLI providers may consume user quota
- CLI providers may require login
- CLI providers may be slow
- CLI output may fail
- Users may not want all pending items to be processed automatically

A safer default behavior:

```text
Mac menu bar badge: 5 pending captures
User clicks: Process All
```

---

## 3.8 Task Views

The app should provide at least three primary views.

### Inbox View

Shows newly captured items and processed drafts that have not yet been confirmed.

### Category View

Shows confirmed todos grouped by user-defined categories.

### Internal Calendar View

Shows tasks by due date or scheduled date. This is an internal calendar-style view and does not sync with Apple Calendar.

---

## 3.9 Widgets and Live Activity

### Widgets

Both Mac and iPhone should support widgets in different sizes.

Suggested widget types:

- Small: Today’s most important task
- Medium: Top tasks from a selected category
- Large: Today + Active Task + Quick Capture
- Interactive widget: Check off checklist items, start active task, or quick capture

### Live Activity

The iPhone app should support Live Activity for the currently active task step.

Example:

```text
Todo: Prepare UCI class meeting
Current step: Draft questionnaire
Next step: Send to Yan for review
```

Live Activity should not be used to display all tasks. It is best suited for the task or step the user is actively working on.

---

## 4. Suggested Data Model

## 4.1 Category

```swift
struct Category {
    var id: UUID
    var name: String
    var description: String
    var formattingInstruction: String
    var schemaPreset: CategorySchemaPreset
    var icon: String?
    var color: String?
    var createdAt: Date
    var updatedAt: Date
}
```

## 4.2 CaptureItem

```swift
struct CaptureItem {
    var id: UUID
    var sourceType: CaptureSourceType
    var sourceText: String?
    var sourceImageAssetId: String?
    var sourceAudioAssetId: String?
    var transcriptText: String?
    var transcriptLanguage: String?
    var userNote: String?
    var createdDevice: DeviceType
    var createdAt: Date
    var status: CaptureStatus
    var preferredProviderMode: ProviderMode
    var assignedProcessorDeviceId: String?
    var processingLockDeviceId: String?
    var processingLockCreatedAt: Date?
    var processingError: String?
}
```

## 4.3 ProcessingDraft

```swift
struct ProcessingDraft {
    var id: UUID
    var captureItemId: UUID
    var recommendedCategoryId: UUID?
    var title: String
    var summary: String?
    var blocks: [TodoBlock]
    var confidence: Double?
    var generatedByProvider: String
    var generatedAt: Date
    var needsClarification: Bool
    var questionsForUser: [String]
}
```

## 4.4 Todo

```swift
struct Todo {
    var id: UUID
    var categoryId: UUID
    var title: String
    var summary: String?
    var blocks: [TodoBlock]
    var status: TodoStatus
    var dueDate: Date?
    var scheduledDate: Date?
    var priority: TodoPriority?
    var createdAt: Date
    var updatedAt: Date
}
```

## 4.5 TodoBlock

```swift
struct TodoBlock {
    var id: UUID
    var todoId: UUID
    var type: TodoBlockType
    var content: String
    var checked: Bool
    var order: Int
}
```

---

## 5. LLM Output Schema

The LLM should return strict JSON instead of free-form Markdown.

Example:

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
    },
    {
      "type": "checkbox",
      "content": "Send the revised questionnaire to Yan for review",
      "checked": false
    },
    {
      "type": "checkbox",
      "content": "Confirm Zoom recording settings",
      "checked": false
    }
  ],
  "dueDateText": "tomorrow before 3 PM",
  "priority": "medium",
  "needsClarification": false,
  "questionsForUser": []
}
```

If the LLM is uncertain, it should return clarification questions:

```json
{
  "needsClarification": true,
  "questionsForUser": [
    "What time is tomorrow's meeting?"
  ]
}
```

---

## 6. Recommended MVP Roadmap

## MVP 1: Core AI Task Inbox

Goal: Validate whether users want to turn messy captured content into structured tasks through AI.

Features:

- Mac + iPhone app
- iCloud sync
- Custom categories
- Text input / paste
- Image import + OCR
- BYOK provider
- LLM draft generation
- Draft review / edit
- Save as Todo
- Inbox View
- Category View

Not included yet:

- CLI provider
- Live Activity
- Widgets
- Mac screen-region capture
- iOS Share Extension
- Apple Reminders / Calendar integration

---

## MVP 2: Voice + CLI Pending Queue

Features:

- Voice input
- Speech-to-text
- Transcript review
- Mac CLI provider
- iPhone pending capture queue
- iCloud sync to Mac
- Mac processes pending items
- Draft syncs back to iPhone
- Retry / failed states

---

## MVP 3: System-level Capture

Features:

- Mac menu bar app
- Global hotkey
- Mac screen-region capture
- iOS Share Extension
- Widgets
- Live Activity

---

## MVP 4: Advanced Power-user Features

Features:

- Local model provider
- Ollama / LM Studio integration
- Provider fallback
- Custom prompts per category
- Batch process pending captures
- Advanced internal calendar-style planning view

---

## 7. Key Product Decisions

1. This product should be positioned as an AI capture inbox, not a traditional Todo app.
2. All AI-generated results should become drafts first and require user approval before becoming final todos.
3. BYOK is the foundation for full cross-device functionality.
4. CLI providers should be Mac-only power-user features.
5. In CLI mode, iPhone should not directly call Mac CLI. It should create pending capture items through iCloud and let Mac process them later.
6. Removing Apple Reminders and Calendar integration significantly reduces complexity.
7. Voice input is a strong fit because it captures tasks that originate directly from the user’s thoughts.
8. The first version should validate the core loop: capture → AI draft → user confirmation → todo.

