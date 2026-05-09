const copy = {
  zh: {
    "nav.workflow": "工作流",
    "nav.surfaces": "产品界面",
    "nav.faq": "常见问题",
    "nav.github": "GitHub",
    "nav.cta": "查看流程",
    "hero.title": "杂乱输入，先成草稿",
    "hero.subtitle": "Lisdo 是 iPhone 和 Mac 上的 AI task inbox。复制文字、导入截图、语音记录或从 Mac 菜单栏捕获内容，先生成草稿，再由你确认保存为分类待办。",
    "hero.primary": "看它如何工作",
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
    "examples.pendingTitle": "正在整理为草稿",
    "examples.pendingBody": "提取文字、匹配分类、等待用户 review",
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
    "faq.a2": "MVP 1 设计为 SwiftData + CloudKit，同步 categories、captures、drafts、todos 和 pending queue metadata。API keys 和 provider secrets 只保存在本机 Keychain。",
    "faq.q3": "截图和图片会上传吗？",
    "faq.a3": "默认策略是本机 Vision OCR，并同步 OCR text 与 metadata；原图默认不通过 iCloud 同步。",
    "faq.q4": "语音和菜单栏捕获都可用了吗？",
    "faq.a4": "Mac 菜单栏捕获目前可用。语音捕获暂不可用，会在核心截图/粘贴转 todo 流程稳定后继续开发。",
    "faq.q5": "Mac 现在可以用吗？iOS 版本呢？",
    "faq.a5": "Mac 端已经开源，现在可以自己 build 使用；但还未完成完整测试和 debug，所以暂时没有安装包。测试完成后会 release 安装包。iOS 版本也在同步开发，完成后会上传 TestFlight。",
    "footer.copy": "Native AI task inbox for iPhone and Mac. Draft-first by design.",
    "footer.github": "GitHub 仓库"
  },
  en: {
    "nav.workflow": "Workflow",
    "nav.surfaces": "App surfaces",
    "nav.faq": "FAQ",
    "nav.github": "GitHub",
    "nav.cta": "See flow",
    "hero.title": "Messy input, clear drafts",
    "hero.subtitle": "Lisdo is an AI task inbox for iPhone and Mac. Paste text, import screenshots, record voice, or capture from the Mac menu bar. AI drafts first, you approve before anything becomes a todo.",
    "hero.primary": "See how it works",
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
    "examples.pendingTitle": "Organizing into draft",
    "examples.pendingBody": "Extracting text, matching category, waiting for review",
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
    "faq.a2": "MVP 1 is designed around SwiftData + CloudKit for categories, captures, drafts, todos, and pending queue metadata. API keys and provider secrets stay in local Keychain.",
    "faq.q3": "Are screenshots and images uploaded?",
    "faq.a3": "The default strategy is local Vision OCR, syncing OCR text and metadata. Original images are not synced through iCloud by default.",
    "faq.q4": "Are voice and menu bar capture ready?",
    "faq.a4": "Mac menu bar capture is available now. Voice capture is not available yet and will continue after the core screenshot/paste-to-todo flow is stable.",
    "faq.q5": "Can I use the Mac app now? What about iOS?",
    "faq.a5": "The Mac app is open source and can be used by building it locally now. There is no installer package yet because full testing and debugging are not finished. An installer will be released after testing. The iOS version is also being developed in parallel and will be uploaded to TestFlight when ready.",
    "footer.copy": "Native AI task inbox for iPhone and Mac. Draft-first by design.",
    "footer.github": "GitHub repo"
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
  updateCaptureExample(currentCapture);
}

function updateCaptureExample(kind) {
  currentCapture = kind;
  const selected = captureExamples[currentLang][kind] || captureExamples[currentLang].text;
  document.querySelector(".example-kind").textContent = selected.kind;
  document.querySelector(".example-title").textContent = selected.title;
  document.querySelector(".example-body").textContent = selected.body;
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
