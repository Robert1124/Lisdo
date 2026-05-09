# Lisdo 中文说明

[English README](README.md)

Lisdo 是一个面向 iPhone 和 Mac 的原生 Apple AI 任务收件箱。它把杂乱输入整理成结构化、可审核的任务草稿，用户确认后才会保存为正式待办。

核心流程：

```text
捕获 -> 文本/OCR 提取 -> LLM 草稿 -> 用户审核 -> 分类待办 -> iCloud 同步
```

Lisdo 的 AI 输出必须先进入草稿状态。没有用户明确审核和确认，LLM 输出不能直接保存成正式待办。

## 主要特性

- 使用 SwiftUI 构建的 iOS 17+ 和 macOS 14+ 原生应用。
- 独立 Swift Package `LisdoCore` 承载共享业务逻辑。
- MVP 1 起使用 SwiftData + CloudKit 做持久化和同步。
- 平台层使用 Apple Vision 做 OCR。
- MVP 1 使用 OpenAI-compatible BYOK provider，并通过 provider abstraction 预留扩展。
- API key 和 provider secrets 只保存在本机 Keychain。
- 包含真实 Widget、Live Activity、Share Extension、macOS menu bar shell targets。
- `Website/` 下包含静态中英文展示页/demo。

## 目录结构

```text
Apps/
  iOS/                iPhone app target
  macOS/              Mac app target
  Shared/             共享平台服务
Extensions/
  Share/              iOS Share Extension shell
  Shared/             共享 ActivityKit attributes
  Widgets/            Widget + Live Activity shell
Packages/
  LisdoCore/          共享 Swift package 和测试
Website/              静态中英文网页/demo
docs/                 产品、设计、架构文档
Design/               App 视觉源文件和资源
project.yml           XcodeGen source of truth
```

## 环境要求

- 安装 Xcode 15+ 的 macOS。
- 部署目标：iOS 17+ / macOS 14+。
- Swift 5.9。
- 使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成 Xcode project。

## 开始开发

生成 Xcode project：

```sh
xcodegen generate
```

打开生成的项目：

```sh
open Lisdo.xcodeproj
```

运行核心测试：

```sh
swift test --package-path Packages/LisdoCore
```

本地预览静态网页：

```sh
cd Website
python3 -m http.server 4173 --bind 127.0.0.1
```

然后打开 `http://127.0.0.1:4173/`。英文是默认版本；中文版本可使用 `?lang=zh`。

## 产品约束

- Lisdo 不是传统 todo app，也不是 website-first 项目。
- 所有 AI 结果必须先进入 draft review flow，才能变成正式 todo。
- API keys、CLI paths、OAuth tokens、provider secrets 不能通过 iCloud 同步。
- MVP 1 不集成 Apple Reminders 或 Apple Calendar。
- 图片默认只同步 OCR 文本和 metadata，不同步原图。

## 开发说明

- `project.yml` 是 Xcode targets 的唯一工程源。
- 生成的 `.xcodeproj` 和 build products 会被 `.gitignore` 忽略。
- `LisdoCore` 负责共享模型、草稿解析、provider contracts、fallback 逻辑、draft-to-todo conversion 和可测试状态转换。
- 平台 targets 负责 SwiftUI 界面、Vision OCR adapters、Keychain 实现、model container wiring 和 extension integration。

## License

Lisdo 使用 MIT License 开源。详见 [LICENSE](LICENSE)。
