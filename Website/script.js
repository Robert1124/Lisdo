const copy = {
  zh: {
    "nav.workflow": "工作流",
    "nav.surfaces": "产品界面",
    "nav.privacy": "隐私",
    "nav.support": "支持",
    "nav.faq": "常见问题",
    "nav.github": "GitHub",
    "nav.sponsor": "赞助",
    "hero.title": "杂乱输入，先成草稿",
    "hero.subtitle": "Lisdo 是 iPhone 和 Mac 上的 AI task inbox。复制文字、导入截图、语音记录或从 Mac 菜单栏捕获内容，先生成草稿，再由你确认保存为分类待办。",
    "hero.primary": "看它如何工作",
    "hero.macDownload": "Mac",
    "hero.testflight": "加入 TestFlight",
    "hero.secondary": "查看 App 组件",
    "mock.sourceScreenshot": "截图 OCR",
    "mock.messyText": "周四 seminar 前把 questionnaire 改完，发给 Yan 看，顺便确认 Zoom recording 设置。",
    "mock.inbox": "Inbox",
    "mock.pastedText": "粘贴文字",
    "mock.draft": "草稿",
    "mock.suggestedCategory": "Work · 建议分类",
    "mock.draftTitle": "准备 UCI study group questionnaire",
    "mock.draftSummary": "修改问卷、发给 Yan 复核，并确认 Zoom 录制设置。",
    "mock.stepOne": "修改 questionnaire",
    "mock.stepTwo": "发给 Yan review",
    "mock.stepThree": "确认 Zoom recording",
    "mock.save": "保存",
    "mock.edit": "编辑",
    "mock.revise": "调整",
    "mock.tabInbox": "收件箱",
    "mock.tabCapture": "捕获",
    "mock.tabPlan": "计划",
    "mock.widgetTitle": "待审核草稿",
    "mock.widgetTask": "3 PM 前 review draft",
    "mock.widgetMeta": "Live Activity shell",
    "workflow.title": "Lisdo 的清晰节奏：先草稿，再保存",
    "workflow.body": "Lisdo 用一个大面板讲清核心动作：不是直接生成待办，而是把捕获内容先变成可检查的 AI 草稿。",
    "workflow.cta": "走一遍流程",
    "workflow.step1Title": "Capture",
    "workflow.step1Body": "文字、截图、照片、语音和 Mac 捕获都进入同一个 inbox。",
    "workflow.step2Title": "Draft",
    "workflow.step2Body": "Vision OCR 和 BYOK provider 生成严格 JSON 草稿。",
    "workflow.step3Title": "Review",
    "workflow.step3Body": "用户编辑标题、摘要、清单、日期和分类。",
    "workflow.step4Title": "Save",
    "workflow.step4Body": "确认后保存为 category todo，并通过 iCloud 同步。",
    "capture.title": "各种输入，都先进入收件箱",
    "capture.subtitle": "Lisdo 把不同 capture source 变成清晰入口，让所有输入先进入同一个 draft-first 工作流。",
    "capture.text": "粘贴文字",
    "capture.ocr": "截图 OCR",
    "capture.voice": "语音记录",
    "capture.mac": "Mac 菜单栏",
    "capture.widget": "Widgets",
    "examples.text.kind": "Pasted text",
    "examples.text.title": "从聊天记录里提取行动项",
    "examples.text.body": "把截图 OCR、课程要求或会议记录粘进 Lisdo，AI 会整理成可审核的 todo 草稿，不直接写入正式待办。",
    "surfaces.title": "截图和粘贴内容，自动整理成 Todo 草稿",
    "surfaces.subtitle": "Lisdo 把截图 OCR 和粘贴文本格式化成包含 reminder、摘要和 bullet points 的可审核 todo。",
    "mac.title": "Lisdo Mac",
    "mac.inbox": "Inbox",
    "mac.drafts": "Drafts",
    "mac.today": "Today",
    "mac.fromPhone": "From iPhone",
    "mac.ready": "3 个草稿待 review",
    "mac.capture": "Capture",
    "mac.cardTitle": "整理 DBH 3210 seminar notes",
    "mac.cardBody": "确认问卷、房间、打印和 Zoom 设置。",
    "mac.pendingTitle": "Waiting for Mac",
    "mac.pendingBody": "iPhone capture 会在 Mac 可用后处理。",
    "review.badge": "Review draft",
    "review.title": "保存前总有一步确认",
    "review.body": "用户可以改分类、标题、摘要、清单和日期。只有点击“保存为待办”后，它才进入正式列表。",
    "format.sourceTab": "截图 OCR",
    "format.pasteTab": "粘贴文字",
    "format.todoBadge": "格式化 Todo 草稿",
    "format.category": "School · 建议分类",
    "format.todoTitle": "准备 Math 22 final exam",
    "format.summary": "把原始截图/粘贴内容整理成可审核的任务，先保留 reminder，再生成 bullet points。",
    "format.reminderLabel": "Reminder",
    "format.reminder": "明天 12:00 PM · Packard 101",
    "format.point1": "中午前到 Packard 101",
    "format.point2": "预留 12 PM-3 PM 考试时间",
    "format.point3": "如需要，确认 extended-time room 安排",
    "story.title": "安静一点，但工作流要完整",
    "story.p1": "Lisdo 的动效轻盈、克制、容易理解。视觉回到原生 Apple 产品：纯净表面、近黑文字、低饱和状态色和克制阴影。",
    "story.p2": "页面避免夸张 AI 营销语言，因为 Lisdo 的价值不是炫技，而是让 messy capture 变成可检查、可同步、可执行的任务。",
    "faq.title": "常见问题",
    "faq.q1": "AI 会不会直接替我创建待办？",
    "faq.a1": "不会。Lisdo 的产品流要求所有 AI 输出先成为 draft。用户 review、编辑并确认后，才保存为正式 todo。",
    "faq.q2": "iPhone 和 Mac 如何同步？",
    "faq.a2": "MVP 1 设计为 SwiftData + CloudKit，同步 categories、captures、drafts、todos 和 pending queue metadata。Hosted BYOK keys 保存在 Keychain，可随用户的 Keychain 同步在 iPhone 和 Mac 可用；CLI paths 和本地 provider 设置不进 CloudKit。",
    "faq.q3": "截图和图片会上传吗？",
    "faq.a3": "默认策略是本机 Vision OCR，并同步 OCR text 与 metadata；原图默认不通过 iCloud 同步。只有 Mac CLI direct media 模式会临时同步原始 image/audio 给 Mac，处理结束后删除 pending media attachment。",
    "faq.q4": "语音和菜单栏捕获都可用了吗？",
    "faq.a4": "Mac 菜单栏捕获目前可用。语音捕获暂不可用，会在核心截图/粘贴转 todo 流程稳定后继续开发。",
    "faq.q6": "隐私和更新说明在哪里？",
    "faq.a6Prefix": "App Store 准备文档包括",
    "faq.privacyLink": "隐私政策",
    "faq.securityLink": "安全和数据处理",
    "faq.supportLink": "支持",
    "faq.and": "和",
    "faq.updatesLink": "更新说明",
    "footer.copy": "Native AI task inbox for iPhone and Mac. Draft-first by design.",
    "footer.privacy": "隐私",
    "footer.security": "安全",
    "footer.support": "支持",
    "footer.updates": "更新",
    "footer.github": "GitHub 仓库",
    "footer.sponsor": "赞助",
    "doc.kicker": "Lisdo 文档",
    "privacy.title": "隐私政策",
    "privacy.intro": "Lisdo 是 iPhone 和 Mac 上的原生任务收件箱。它围绕本地审核、iCloud 同步和用户控制的 AI provider 设置设计。",
    "privacy.updated": "最后更新：2026 年 5 月 9 日",
    "privacy.summaryTitle": "概要",
    "privacy.summaryBody": "Lisdo 不出售个人数据，不展示广告，也不包含用于广告的第三方追踪。捕获内容会先变成 AI 草稿，必须由用户审核并确认后才会保存为正式 todo。",
    "privacy.infoTitle": "Lisdo 会处理的信息",
    "privacy.info1": "Categories、captures、drafts、todos、todo blocks 以及相关状态 metadata。",
    "privacy.info2": "你输入、粘贴、导入、分享或通过 OCR 提取的文本。",
    "privacy.info3": "语音捕获可用后的转写文本。",
    "privacy.info4": "处理 capture 所需的可选图片、音频或文件 metadata。",
    "privacy.info5": "本地 provider 配置，例如 provider mode 和 endpoint settings。",
    "privacy.icloudTitle": "iCloud 同步",
    "privacy.icloudBody1": "Lisdo 使用 Apple iCloud 基础设施在 iPhone 和 Mac 之间同步 app 数据。同步数据可能包括 categories、capture items、processing drafts、todos、todo blocks 和 pending queue metadata。同步行为受你的 iCloud 账号和 Apple 隐私控制管理。",
    "privacy.icloudBody2": "Lisdo 不会把 API keys、provider secrets、OAuth tokens 或本地 CLI paths 存进 CloudKit app database。Hosted BYOK API keys 保存在 Keychain，并可能通过你的 Apple Keychain 同步设置在设备间可用。本地 CLI paths 和 local-only provider settings 留在配置它们的 Mac 上。",
    "privacy.byokTitle": "BYOK AI 处理",
    "privacy.byokBody1": "Lisdo 的 MVP provider 模式是 bring-your-own-key。当你选择整理一条 capture 时，相关文本、OCR 文本、转写内容、category rules 和 draft instructions 可能会发送给你配置的 AI provider。Provider 的处理方式由该 provider 的条款和隐私政策约束。",
    "privacy.byokBody2": "Provider credentials 保存在 Keychain。Hosted BYOK keys 可以通过用户的 Keychain sync 在 iPhone 和 Mac 上可用，以便两端处理草稿；它们不会作为 CloudKit records 保存。",
    "privacy.mediaTitle": "图片、音频和原始媒体",
    "privacy.mediaBody1": "Lisdo 的默认设计是在捕获或导入图片的设备上运行 Apple Vision OCR，然后同步 OCR 文本和 metadata，而不是同步原图。音频捕获设计为把 transcript 处理和 AI 草稿分开。",
    "privacy.mediaBody2": "对于 Mac-only CLI 或本地模型模式，直接处理图片或音频时，原始媒体可能会作为 pending attachment 临时同步到 Mac。Mac 处理完成或进入终态失败后，Lisdo 会删除这些临时 pending media attachments。Lisdo 不会通过 CloudKit app database 发送 provider secrets 或 CLI paths。",
    "privacy.contactTitle": "联系",
    "privacy.contactPrefix": "如有隐私或数据处理问题，请通过",
    "privacy.contactLink": "支持页面",
    "privacy.contactSuffix": "联系支持。",
    "security.title": "安全和数据处理",
    "security.intro": "Lisdo 把 AI 输出视为草稿内容，将 provider 密钥保存在本地，并使用 Apple 平台存储 app 数据和同步。",
    "security.draftTitle": "AI 草稿优先",
    "security.draftBody": "AI 生成内容不会自动保存为正式 todo。Lisdo 会先创建草稿，展示来源上下文和建议分类，并要求用户审核后才能保存 todo。",
    "security.secretsTitle": "密钥",
    "security.secretsBody": "BYOK API keys 和 provider secrets 保存在 Keychain，而不是 SwiftData 或 CloudKit records。Hosted BYOK keys 可能通过用户的 Apple Keychain sync 设置同步，让 iPhone 和 Mac 都能处理草稿。OAuth tokens、CLI paths 和 local-only provider settings 保持本地，不应该出现在生产日志里。",
    "security.syncTitle": "同步边界",
    "security.syncBody": "SwiftData 和 CloudKit 同步 categories、captures、drafts、todos、todo blocks 和 pending queue metadata 等 app records。原始图片和音频文件默认不同步；预期同步 payload 是提取后的文本和 metadata。如果启用 Mac CLI direct media processing，原始图片或音频可能会作为 pending raw attachment 临时同步，然后在处理进入最终状态后删除。",
    "security.providerTitle": "Provider 边界",
    "security.providerBody1": "当你整理一条 capture 时，Lisdo 只会把生成该草稿所需的内容发送给你配置的 provider。对于 OpenAI-compatible BYOK endpoint，这可能包括 source text、OCR text、category instructions 和 strict JSON draft request。",
    "security.providerBody2": "未来的 Mac CLI 或本地模型模式设计为在你的 Mac 上运行。如果为本地命令启用 direct raw media processing，该命令可能会收到完成任务所需的原始媒体。只使用你信任的 CLI 工具和本地服务。",
    "security.trackingTitle": "无追踪和广告",
    "security.trackingBody": "Lisdo 不是围绕广告或跨 app 追踪构建的。这个静态网站不需要 analytics scripts 才能阅读这些政策页面。",
    "security.reportTitle": "报告安全问题",
    "security.reportPrefix": "请通过",
    "security.reportLink": "支持页面",
    "security.reportSuffix": "联系我们，并附上受影响的平台、app 版本和问题简述。",
    "support.title": "支持",
    "support.intro": "获取 capture、草稿审核、iCloud 同步、BYOK provider 设置和 Mac 更新行为方面的帮助。",
    "support.contactTitle": "联系",
    "support.contactPrefix": "需要支持时，请在",
    "support.repoLink": "Lisdo GitHub 仓库",
    "support.contactSuffix": "打开 issue，或通过仓库资料联系 maintainer。请附上平台、app 版本、OS 版本，以及问题是否影响 capture、OCR、AI 草稿、review 或 sync。",
    "support.beforeTitle": "提交报告前",
    "support.before1": "确认每台设备都已启用 iCloud Drive 和 app 的 iCloud 访问。",
    "support.before2": "确认处理草稿的设备上，BYOK provider key 可以在 Keychain 中使用。",
    "support.before3": "检查 capture 是否仍是 draft 或 pending item，而不是已经保存的 todo。",
    "support.before4": "对于 Mac CLI 模式，请确认本地命令已安装且可信。",
    "support.commonTitle": "常见问题",
    "support.q1": "Lisdo 会自动保存 AI 输出吗？",
    "support.a1": "不会。AI 输出会停留在 draft review 中，直到你确认保存。",
    "support.q2": "为什么我的 API key 没有出现在另一台设备上？",
    "support.a2": "Hosted BYOK keys 使用 Keychain 存储，并可通过 Apple Keychain sync 同步。如果 key 缺失，请确认两台设备的 Apple 账号都启用了 Keychain sync，或在需要处理草稿的设备上重新添加 key。",
    "support.q3": "更新说明在哪里？",
    "support.a3Prefix": "Mac 和 iOS 下载状态记录在",
    "support.a3Link": "更新页面",
    "support.a3Suffix": "。",
    "support.linksTitle": "TestFlight",
    "support.linksBody": "iOS TestFlight 已开放测试。公开 App Store 版本发布后会继续更新链接。开发状态以 GitHub 仓库为准。",
    "support.testflightLink": "加入 TestFlight",
    "updates.title": "App 和更新说明",
    "updates.intro": "查看最新 GitHub Releases，并在公开构建可用时下载 Mac 或 iOS 版本。",
    "updates.releasesTitle": "GitHub Releases",
    "updates.releasesLoading": "正在载入 GitHub Releases...",
    "updates.releasesEmpty": "暂无公开 release。开发状态仍以 GitHub 仓库为准。",
    "updates.releasesError": "暂时无法载入 GitHub Releases。请直接查看 GitHub 仓库。",
    "updates.downloadTitle": "下载",
    "updates.downloadBody": "Mac 公开构建会发布在 GitHub Releases。iOS beta 测试现在可以通过 TestFlight 加入。",
    "updates.macDownload": "Mac 下载",
    "updates.iosDownload": "TestFlight",
    "updates.dataTitle": "数据处理变更",
    "updates.dataPrefix": "任何改变同步行为、provider 请求、原始媒体处理或密钥存储的更新，都应该在发布前同步更新",
    "updates.dataPrivacy": "隐私政策",
    "updates.dataAnd": "以及",
    "updates.dataSecurity": "安全和数据处理",
    "updates.dataSuffix": "页面。",
    "release.view": "查看 release",
    "release.prerelease": "预发布",
    "release.published": "发布于"
  },
  en: {
    "nav.workflow": "Workflow",
    "nav.surfaces": "App surfaces",
    "nav.privacy": "Privacy",
    "nav.support": "Support",
    "nav.faq": "FAQ",
    "nav.github": "GitHub",
    "nav.sponsor": "Sponsor",
    "hero.title": "Messy input, clear drafts",
    "hero.subtitle": "Lisdo is an AI task inbox for iPhone and Mac. Paste text, import screenshots, record voice, or capture from the Mac menu bar. AI drafts first, you approve before anything becomes a todo.",
    "hero.primary": "See how it works",
    "hero.macDownload": "Mac",
    "hero.testflight": "Join TestFlight",
    "hero.secondary": "View app components",
    "mock.sourceScreenshot": "Screenshot OCR",
    "mock.messyText": "Before Thursday seminar, revise the questionnaire, send it to Yan, and confirm the Zoom recording settings.",
    "mock.inbox": "Inbox",
    "mock.pastedText": "Pasted text",
    "mock.draft": "Draft",
    "mock.suggestedCategory": "Work · suggested",
    "mock.draftTitle": "Prepare UCI study group questionnaire",
    "mock.draftSummary": "Revise the questionnaire, send it to Yan, and confirm Zoom recording.",
    "mock.stepOne": "Revise questionnaire",
    "mock.stepTwo": "Send to Yan for review",
    "mock.stepThree": "Confirm Zoom recording",
    "mock.save": "Save",
    "mock.edit": "Edit",
    "mock.revise": "Revise",
    "mock.tabInbox": "Inbox",
    "mock.tabCapture": "Capture",
    "mock.tabPlan": "Plan",
    "mock.widgetTitle": "Review queue",
    "mock.widgetTask": "Review draft before 3 PM",
    "mock.widgetMeta": "Live Activity shell",
    "workflow.title": "Lisdo's draft-first rhythm, from capture to review",
    "workflow.body": "Lisdo explains one core action with a focused panel: captures become reviewable AI drafts before anything can be saved as a todo.",
    "workflow.cta": "Walk the flow",
    "workflow.step1Title": "Capture",
    "workflow.step1Body": "Text, screenshots, photos, voice notes, and Mac captures enter one inbox.",
    "workflow.step2Title": "Draft",
    "workflow.step2Body": "Vision OCR and a BYOK provider create strict JSON drafts.",
    "workflow.step3Title": "Review",
    "workflow.step3Body": "Edit title, summary, checklist, date, and category.",
    "workflow.step4Title": "Save",
    "workflow.step4Body": "After approval, save as a category todo and sync with iCloud.",
    "capture.title": "Every input starts in the inbox",
    "capture.subtitle": "Lisdo turns different capture sources into clear entry points so every input starts in the same draft-first workflow.",
    "capture.text": "Text paste",
    "capture.ocr": "Screenshot OCR",
    "capture.voice": "Voice note",
    "capture.mac": "Mac menu bar",
    "capture.widget": "Widgets",
    "examples.text.kind": "Pasted text",
    "examples.text.title": "Extract actions from a chat log",
    "examples.text.body": "Paste screenshot OCR, course requirements, or meeting notes into Lisdo. AI creates a reviewable todo draft instead of writing directly into your todo list.",
    "surfaces.title": "Screenshots and pasted text become todo drafts",
    "surfaces.subtitle": "Lisdo formats screenshot OCR and pasted text into a reviewable todo with a reminder, summary, and bullet points.",
    "mac.title": "Lisdo Mac",
    "mac.inbox": "Inbox",
    "mac.drafts": "Drafts",
    "mac.today": "Today",
    "mac.fromPhone": "From iPhone",
    "mac.ready": "3 drafts ready",
    "mac.capture": "Capture",
    "mac.cardTitle": "Organize DBH 3210 seminar notes",
    "mac.cardBody": "Confirm questionnaire, room, printing, and Zoom settings.",
    "mac.pendingTitle": "Waiting for Mac",
    "mac.pendingBody": "iPhone capture will process when Mac is available.",
    "review.badge": "Review draft",
    "review.title": "There is always a review step before saving",
    "review.body": "Change the category, title, summary, checklist, and date. It only becomes a real todo after you tap save.",
    "format.sourceTab": "Screenshot OCR",
    "format.pasteTab": "Pasted text",
    "format.todoBadge": "Formatted todo draft",
    "format.category": "School · suggested",
    "format.todoTitle": "Prepare for Math 22 final exam",
    "format.summary": "Raw screenshot or pasted text becomes a reviewable task with the reminder preserved and bullet points generated.",
    "format.reminderLabel": "Reminder",
    "format.reminder": "Tomorrow at 12:00 PM · Packard 101",
    "format.point1": "Be at Packard 101 before noon",
    "format.point2": "Block 12 PM-3 PM for the exam",
    "format.point3": "Confirm extended-time room instructions if needed",
    "story.title": "Quiet by design, complete in workflow",
    "story.p1": "Lisdo's motion is light, restrained, and easy to understand. The visuals stay close to a native Apple product: clean surfaces, near-black ink, low-saturation status colors, and restrained shadows.",
    "story.p2": "The page avoids hype-heavy AI language because Lisdo's value is not spectacle. It turns messy capture into reviewable, syncable, actionable tasks.",
    "faq.title": "FAQ",
    "faq.q1": "Will AI create todos for me automatically?",
    "faq.a1": "No. Lisdo requires AI output to become a draft first. The user reviews, edits, and approves before it becomes a final todo.",
    "faq.q2": "How do iPhone and Mac sync?",
    "faq.a2": "MVP 1 is designed around SwiftData + CloudKit for categories, captures, drafts, todos, and pending queue metadata. Hosted BYOK keys are stored in Keychain and can be available on iPhone and Mac through the user's Keychain sync; CLI paths and local provider settings do not enter CloudKit.",
    "faq.q3": "Are screenshots and images uploaded?",
    "faq.a3": "The default strategy is local Vision OCR, syncing OCR text and metadata. Original images are not synced through iCloud by default. Mac CLI direct media mode is the exception: it temporarily syncs original image/audio to the Mac, then deletes the pending media attachment after processing.",
    "faq.q4": "Are voice and menu bar capture ready?",
    "faq.a4": "Mac menu bar capture is available now. Voice capture is not available yet and will continue after the core screenshot/paste-to-todo flow is stable.",
    "faq.q6": "Where are privacy and update details?",
    "faq.a6Prefix": "App Store readiness documentation includes the",
    "faq.privacyLink": "Privacy Policy",
    "faq.securityLink": "Security and Data Handling",
    "faq.supportLink": "Support",
    "faq.and": "and",
    "faq.updatesLink": "Updates",
    "footer.copy": "Native AI task inbox for iPhone and Mac. Draft-first by design.",
    "footer.privacy": "Privacy",
    "footer.security": "Security",
    "footer.support": "Support",
    "footer.updates": "Updates",
    "footer.github": "GitHub repo",
    "footer.sponsor": "Sponsor",
    "doc.kicker": "Lisdo documentation",
    "privacy.title": "Privacy Policy",
    "privacy.intro": "Lisdo is a native task inbox for iPhone and Mac. It is designed around local review, iCloud sync, and user-controlled AI provider settings.",
    "privacy.updated": "Last updated: May 9, 2026",
    "privacy.summaryTitle": "Summary",
    "privacy.summaryBody": "Lisdo does not sell personal data, does not show ads, and does not include third-party tracking for advertising. Captures become AI drafts first, and a user must review and approve a draft before it becomes a saved todo.",
    "privacy.infoTitle": "Information Lisdo Handles",
    "privacy.info1": "Categories, captures, drafts, todos, todo blocks, and related status metadata.",
    "privacy.info2": "Text you type, paste, import, share, or extract through OCR.",
    "privacy.info3": "Transcripts when voice capture is available.",
    "privacy.info4": "Optional image, audio, or file metadata needed to process a capture.",
    "privacy.info5": "Local provider configuration such as provider mode and endpoint settings.",
    "privacy.icloudTitle": "iCloud Sync",
    "privacy.icloudBody1": "Lisdo uses Apple iCloud infrastructure to sync app data between your iPhone and Mac. Synced data may include categories, capture items, processing drafts, todos, todo blocks, and pending queue metadata. Your iCloud account and Apple privacy controls govern this sync.",
    "privacy.icloudBody2": "Lisdo does not store API keys, provider secrets, OAuth tokens, or local CLI paths in the CloudKit app database. Hosted BYOK API keys are stored in Keychain and may be available on your devices through your Apple Keychain sync settings. Local CLI paths and local-only provider settings stay on the Mac where they were configured.",
    "privacy.byokTitle": "BYOK AI Processing",
    "privacy.byokBody1": "Lisdo's MVP provider model is bring-your-own-key. When you choose to organize a capture, the relevant text, OCR text, transcript, category rules, and draft instructions may be sent to the AI provider you configured. Provider handling is governed by that provider's terms and privacy policy.",
    "privacy.byokBody2": "Provider credentials are stored in Keychain. Hosted BYOK keys may sync through the user's Keychain sync so iPhone and Mac can process drafts with the same provider credentials; they are not stored as CloudKit records.",
    "privacy.mediaTitle": "Images, Audio, And Raw Media",
    "privacy.mediaBody1": "Lisdo's default design is to run Apple Vision OCR on the device where an image is captured or imported, then sync OCR text and metadata rather than the original image. Audio capture is designed to keep transcript handling separate from AI drafting.",
    "privacy.mediaBody2": "For Mac-only CLI or local-model modes, direct image or audio processing may temporarily sync the original media to the Mac as a pending attachment. After Mac processing reaches a completed or terminal failed state, Lisdo deletes those temporary pending media attachments. Lisdo does not send provider secrets or CLI paths through the CloudKit app database.",
    "privacy.contactTitle": "Contact",
    "privacy.contactPrefix": "For privacy questions or data handling requests, contact support through the options on the ",
    "privacy.contactLink": "Support page",
    "privacy.contactSuffix": ".",
    "security.title": "Security And Data Handling",
    "security.intro": "Lisdo treats AI output as draft material, keeps provider secrets local, and uses Apple platform storage for app data and sync.",
    "security.draftTitle": "Draft-First AI",
    "security.draftBody": "AI-generated content is not saved as a final todo automatically. Lisdo creates a draft, shows the source context and suggested category, and requires user review before a todo is saved.",
    "security.secretsTitle": "Secrets",
    "security.secretsBody": "BYOK API keys and provider secrets are stored in Keychain, not in SwiftData or CloudKit records. Hosted BYOK keys may sync through the user's Apple Keychain sync settings so both iPhone and Mac can process drafts. OAuth tokens, CLI paths, and local-only provider settings stay local and should not appear in production logs.",
    "security.syncTitle": "Sync Boundary",
    "security.syncBody": "SwiftData and CloudKit sync app records such as categories, captures, drafts, todos, todo blocks, and pending queue metadata. Original images and audio files are not synced by default; the expected synced payload is extracted text and metadata. If Mac CLI direct media processing is enabled, the original image or audio may be temporarily synced as a pending raw attachment, then deleted after processing reaches a final state.",
    "security.providerTitle": "Provider Boundary",
    "security.providerBody1": "When you organize a capture, Lisdo sends only the content needed for that draft to your configured provider. For an OpenAI-compatible BYOK endpoint, this can include source text, OCR text, category instructions, and the strict JSON draft request.",
    "security.providerBody2": "Future Mac CLI or local-model modes are designed to run on your Mac. If direct raw media processing is enabled for a local command, that command may receive the raw media needed for the job. Use only CLI tools and local services you trust.",
    "security.trackingTitle": "No Tracking Or Ads",
    "security.trackingBody": "Lisdo is not built around advertising or cross-app tracking. The static website does not require analytics scripts to read these policy pages.",
    "security.reportTitle": "Reporting A Security Issue",
    "security.reportPrefix": "Please use the contact options on the ",
    "security.reportLink": "Support page",
    "security.reportSuffix": " and include the affected platform, app version, and a short description of the issue.",
    "support.title": "Support",
    "support.intro": "Get help with capture, draft review, iCloud sync, BYOK provider setup, and Mac update behavior.",
    "support.contactTitle": "Contact",
    "support.contactPrefix": "For support, open an issue in the ",
    "support.repoLink": "Lisdo GitHub repository",
    "support.contactSuffix": " or contact the maintainer through the repository profile. Include your platform, app version, OS version, and whether the issue affects capture, OCR, AI drafting, review, or sync.",
    "support.beforeTitle": "Before Sending A Report",
    "support.before1": "Confirm iCloud Drive and app iCloud access are enabled on each device.",
    "support.before2": "Confirm your BYOK provider key is available in Keychain on the device that is processing drafts.",
    "support.before3": "Check whether a capture is still a draft or pending item rather than a saved todo.",
    "support.before4": "For Mac CLI modes, confirm the local command is installed and trusted.",
    "support.commonTitle": "Common Questions",
    "support.q1": "Does Lisdo save AI output automatically?",
    "support.a1": "No. AI output stays in draft review until you approve it.",
    "support.q2": "Why does my API key not appear on another device?",
    "support.a2": "Hosted BYOK keys use Keychain storage and can sync through Apple Keychain sync. If the key is missing, confirm Keychain sync is enabled for the Apple account on both devices or add the key again on the device that should process drafts.",
    "support.q3": "Where are update notes?",
    "support.a3Prefix": "Mac and iOS download status is documented on the ",
    "support.a3Link": "Updates page",
    "support.a3Suffix": ".",
    "support.linksTitle": "TestFlight",
    "support.linksBody": "The iOS TestFlight is open for testing now. App Store links will be added when public builds are available. Development status is tracked in the GitHub repository.",
    "support.testflightLink": "Join TestFlight",
    "updates.title": "App And Update Notes",
    "updates.intro": "View the latest GitHub Releases and download Mac or iOS builds when public artifacts are available.",
    "updates.releasesTitle": "GitHub Releases",
    "updates.releasesLoading": "Loading GitHub Releases...",
    "updates.releasesEmpty": "No public releases are available yet. Development status remains available in the GitHub repository.",
    "updates.releasesError": "GitHub Releases could not be loaded right now. Open the GitHub repository for the latest status.",
    "updates.downloadTitle": "Downloads",
    "updates.downloadBody": "Mac public builds are published through GitHub Releases. iOS beta testing is available through TestFlight.",
    "updates.macDownload": "Mac download",
    "updates.iosDownload": "TestFlight",
    "updates.dataTitle": "Data Handling Changes",
    "updates.dataPrefix": "Any update that changes sync behavior, provider requests, raw media handling, or secret storage should update the ",
    "updates.dataPrivacy": "Privacy Policy",
    "updates.dataAnd": " and ",
    "updates.dataSecurity": "Security And Data Handling",
    "updates.dataSuffix": " pages before release.",
    "release.view": "View release",
    "release.prerelease": "Prerelease",
    "release.published": "Published"
  }
};

const captureExamples = {
  zh: {
    text: {
      kind: "Pasted text",
      title: "从聊天记录里提取行动项",
      body: "把 email、课程要求或会议记录粘进 Lisdo，AI 只生成可审核草稿，不直接写入正式待办。"
    },
    ocr: {
      kind: "Screenshot OCR",
      title: "从截图中读出任务",
      body: "Vision 在本机提取 OCR 文本，再由 provider 生成结构化草稿，原图默认不通过 iCloud 同步。"
    },
    voice: {
      kind: "Voice note",
      title: "语音先变 transcript",
      body: "语音和 LLM 整理分开处理，用户可以先检查 transcript，再重新生成或调整草稿。"
    },
    mac: {
      kind: "Mac menu bar",
      title: "在 Mac 上处理 pending captures",
      body: "iPhone 捕获的 pending item 可以同步到 Mac，由 Mac 端处理后把 draft 同步回来。"
    },
    widget: {
      kind: "Widget shell",
      title: "系统级入口保持产品状态",
      body: "Widget 和 Live Activity shell 展示 focus、inbox summary 和 active task，而不是空白占位。"
    }
  },
  en: {
    text: {
      kind: "Pasted text",
      title: "Extract actions from a chat log",
      body: "Paste email, course requirements, or meeting notes into Lisdo. AI creates a reviewable draft instead of writing directly into your todo list."
    },
    ocr: {
      kind: "Screenshot OCR",
      title: "Read tasks from screenshots",
      body: "Vision extracts text locally, then the provider creates a structured draft. Original images are not synced through iCloud by default."
    },
    voice: {
      kind: "Voice note",
      title: "Voice becomes transcript first",
      body: "Speech-to-text and LLM organization are separate so users can review the transcript and regenerate drafts without recording again."
    },
    mac: {
      kind: "Mac menu bar",
      title: "Process pending captures on Mac",
      body: "Pending captures from iPhone can sync to Mac, process there, and send reviewable drafts back to iPhone."
    },
    widget: {
      kind: "Widget shell",
      title: "System surfaces stay intentional",
      body: "Widget and Live Activity shells show focus, inbox summary, and active task states instead of empty placeholders."
    }
  }
};

let currentLang = new URLSearchParams(window.location.search).get("lang") === "zh" ? "zh" : "en";
let currentCapture = "text";
let releaseState = {
  status: "idle",
  releases: []
};

function applyLanguage(lang) {
  currentLang = lang;
  document.documentElement.lang = lang === "en" ? "en" : "zh-CN";
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    if (copy[lang][key]) {
      node.textContent = copy[lang][key];
    }
  });
  document.querySelectorAll("[data-lang-option]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.langOption === lang));
  });
  const url = new URL(window.location.href);
  if (lang === "en") {
    url.searchParams.delete("lang");
  } else {
    url.searchParams.set("lang", "zh");
  }
  history.replaceState({}, "", url);
  if (document.querySelector(".example-kind")) {
    updateCaptureExample(currentCapture);
  }
  renderReleases();
}

function updateCaptureExample(kind) {
  currentCapture = kind;
  const selected = captureExamples[currentLang][kind] || captureExamples[currentLang].text;
  const kindNode = document.querySelector(".example-kind");
  const titleNode = document.querySelector(".example-title");
  const bodyNode = document.querySelector(".example-body");
  if (!kindNode || !titleNode || !bodyNode) {
    return;
  }
  kindNode.textContent = selected.kind;
  titleNode.textContent = selected.title;
  bodyNode.textContent = selected.body;
}

function formatDate(value) {
  return new Intl.DateTimeFormat(currentLang === "zh" ? "zh-CN" : "en", {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(new Date(value));
}

function releaseSummary(body) {
  const text = (body || "").replace(/[#>*_`[\]-]/g, "").replace(/\s+/g, " ").trim();
  if (!text) {
    return "";
  }
  return text.length > 220 ? `${text.slice(0, 217)}...` : text;
}

function renderReleases() {
  const list = document.querySelector("[data-release-list]");
  if (!list) {
    return;
  }

  if (releaseState.status === "loading") {
    list.innerHTML = `<p class="release-empty">${copy[currentLang]["updates.releasesLoading"]}</p>`;
    return;
  }

  if (releaseState.status === "error") {
    list.innerHTML = `<p class="release-empty">${copy[currentLang]["updates.releasesError"]}</p>`;
    return;
  }

  if (!releaseState.releases.length) {
    list.innerHTML = `<p class="release-empty">${copy[currentLang]["updates.releasesEmpty"]}</p>`;
    return;
  }

  list.innerHTML = releaseState.releases.slice(0, 6).map((release) => {
    const name = release.name || release.tag_name;
    const note = releaseSummary(release.body);
    const prerelease = release.prerelease ? ` · ${copy[currentLang]["release.prerelease"]}` : "";
    return `
      <article class="release-item">
        <h3>${escapeHTML(name)}</h3>
        <div class="release-meta">${copy[currentLang]["release.published"]} ${formatDate(release.published_at)} · ${escapeHTML(release.tag_name)}${prerelease}</div>
        ${note ? `<p class="release-note">${escapeHTML(note)}</p>` : ""}
        <p><a href="${escapeHTML(release.html_url)}" target="_blank" rel="noopener noreferrer">${copy[currentLang]["release.view"]}</a></p>
      </article>
    `;
  }).join("");
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;"
  })[char]);
}

async function loadGitHubReleases() {
  const list = document.querySelector("[data-release-list]");
  if (!list) {
    return;
  }

  releaseState = { status: "loading", releases: [] };
  renderReleases();

  try {
    const response = await fetch("https://api.github.com/repos/Robert1124/Lisdo/releases", {
      headers: { Accept: "application/vnd.github+json" }
    });
    if (!response.ok) {
      throw new Error(`GitHub releases request failed: ${response.status}`);
    }
    const releases = await response.json();
    releaseState = {
      status: "ready",
      releases: Array.isArray(releases) ? releases : []
    };
  } catch (error) {
    releaseState = { status: "error", releases: [] };
  }

  renderReleases();
}

document.querySelectorAll("[data-lang-option]").forEach((button) => {
  button.addEventListener("click", () => applyLanguage(button.dataset.langOption));
});

document.querySelectorAll(".capture-pill").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".capture-pill").forEach((pill) => {
      pill.classList.remove("is-active");
      pill.setAttribute("aria-selected", "false");
    });
    button.classList.add("is-active");
    button.setAttribute("aria-selected", "true");
    updateCaptureExample(button.dataset.capture);
  });
});

document.querySelectorAll(".faq-item button").forEach((button) => {
  button.addEventListener("click", () => {
    const expanded = button.getAttribute("aria-expanded") === "true";
    const panel = button.nextElementSibling;
    button.setAttribute("aria-expanded", String(!expanded));
    panel.hidden = expanded;
  });
});

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
if (prefersReducedMotion) {
  document.querySelectorAll(".reveal").forEach((node) => node.classList.add("is-visible"));
} else if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.16 }
  );
  document.querySelectorAll(".reveal").forEach((node) => observer.observe(node));
} else {
  document.querySelectorAll(".reveal").forEach((node) => node.classList.add("is-visible"));
}

applyLanguage(currentLang);
loadGitHubReleases();
