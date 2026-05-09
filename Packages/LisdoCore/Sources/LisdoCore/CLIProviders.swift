import Foundation

public enum CLIProviderKind: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode
    case gemini
}

public struct CLIDraftProviderDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: CLIProviderKind
    public var executableName: String
    public var defaultArguments: [String]
    public var defaultTimeoutSeconds: TimeInterval

    public init(
        id: String,
        displayName: String,
        kind: CLIProviderKind,
        executableName: String,
        defaultArguments: [String] = [],
        defaultTimeoutSeconds: TimeInterval = 120
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.executableName = executableName
        self.defaultArguments = defaultArguments
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
    }

    public static func codex(defaultTimeoutSeconds: TimeInterval = 120) -> CLIDraftProviderDescriptor {
        CLIDraftProviderDescriptor(
            id: "codex-cli",
            displayName: "Codex CLI",
            kind: .codex,
            executableName: "codex",
            defaultArguments: [],
            defaultTimeoutSeconds: defaultTimeoutSeconds
        )
    }

    public static func claudeCode(defaultTimeoutSeconds: TimeInterval = 120) -> CLIDraftProviderDescriptor {
        CLIDraftProviderDescriptor(
            id: "claude-code",
            displayName: "Claude Code CLI",
            kind: .claudeCode,
            executableName: "claude",
            defaultArguments: [],
            defaultTimeoutSeconds: defaultTimeoutSeconds
        )
    }

    public static func gemini(defaultTimeoutSeconds: TimeInterval = 120) -> CLIDraftProviderDescriptor {
        CLIDraftProviderDescriptor(
            id: "gemini-cli",
            displayName: "Gemini CLI",
            kind: .gemini,
            executableName: "gemini",
            defaultArguments: [],
            defaultTimeoutSeconds: defaultTimeoutSeconds
        )
    }
}

public struct CLIDraftCommandInvocation: Equatable, Sendable {
    public var provider: CLIDraftProviderDescriptor
    public var executableName: String
    public var executablePath: String?
    public var arguments: [String]
    public var environment: [String: String]
    public var prompt: String
    public var timeoutSeconds: TimeInterval

    public init(
        provider: CLIDraftProviderDescriptor,
        executableName: String,
        executablePath: String? = nil,
        arguments: [String],
        environment: [String: String] = [:],
        prompt: String,
        timeoutSeconds: TimeInterval
    ) {
        self.provider = provider
        self.executableName = executableName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.prompt = prompt
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct CLIDraftCommandResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public var timedOut: Bool

    public init(stdout: String, stderr: String = "", exitCode: Int32 = 0, timedOut: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

public protocol CLIDraftCommandRunning: Sendable {
    func run(_ command: CLIDraftCommandInvocation) async throws -> CLIDraftCommandResult
}

public protocol CLIDraftCommandBuilding: Sendable {
    func makeCommand(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> CLIDraftCommandInvocation
}

public struct CLIDraftCommandStrategy: CLIDraftCommandBuilding {
    public var provider: CLIDraftProviderDescriptor

    public init(provider: CLIDraftProviderDescriptor) {
        self.provider = provider
    }

    public func makeCommand(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> CLIDraftCommandInvocation {
        let prompt = Self.makePrompt(input: input, categories: categories, options: options)
        return CLIDraftCommandInvocation(
            provider: provider,
            executableName: provider.executableName,
            executablePath: nil,
            arguments: provider.defaultArguments + providerPromptArguments(prompt),
            environment: [:],
            prompt: prompt,
            timeoutSeconds: provider.defaultTimeoutSeconds
        )
    }

    private func providerPromptArguments(_ prompt: String) -> [String] {
        switch provider.kind {
        case .codex, .claudeCode, .gemini:
            return ["--prompt", prompt]
        }
    }

    private static func makePrompt(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> String {
        let categoryLines = categories.map { category in
            "- id: \(category.id), name: \(category.name), preset: \(category.schemaPreset.rawValue), description: \(category.descriptionText), format: \(category.formattingInstruction)"
        }
        .joined(separator: "\n")

        let userNoteLine = input.userNote.map { "\nUser note: \($0)" } ?? ""
        let preferredPresetLine = input.preferredSchemaPreset.map { "\nPreferred schema preset: \($0.rawValue)" } ?? ""
        let revisionInstructionLine = input.revisionInstructions.map {
            "\nRevision instructions: \($0)\nApply these instructions while keeping the result a draft for user review."
        } ?? ""
        let maximumOutputLine = options.maximumOutputTokens.map { "\nMaximum output tokens: \($0)" } ?? ""
        let captureContext = captureContextLines(input: input)

        return """
        You generate draft tasks for Lisdo. Return only strict JSON matching this shape:
        {"recommendedCategoryId":"category-id-or-null","confidence":0.0,"title":"short title","summary":"optional summary","blocks":[{"type":"checkbox|bullet|note","content":"text","checked":false}],"suggestedReminders":[{"title":"advance reminder title","reminderDateText":"natural language reminder date","reminderDateISO":"ISO-8601 notification time or null","reason":"why this reminder helps","defaultSelected":true,"order":0}],"dueDateText":"optional natural language due date","dueDateISO":"ISO-8601 deadline or null","scheduledDateISO":"ISO-8601 event/start time or null","dateResolutionReferenceISO":"ISO-8601 timestamp used to resolve relative dates or null","priority":"low|medium|high|null","needsClarification":false,"questionsForUser":[]}
        Resolve relative dates like today, tomorrow, tonight, this Friday, and the day before into ISO-8601 timestamps with timezone offsets when enough context exists.
        Use dueDateISO for deadlines and due-by times. Use scheduledDateISO for events, appointments, classes, meetings, or concrete start times.
        Use the source timestamp first when the source includes one; otherwise use the capture context supplied below. Preserve the original natural phrase in dueDateText. If the date is ambiguous, leave ISO fields null and ask a clarification question.
        Use suggestedReminders for preparatory or advance reminders under the main todo; do not put those as normal checklist blocks when they are separate reminders. Add reminderDateISO when the reminder time can be resolved to a concrete notification time. Examples: run a tech check the day before, update the computer the day before.
        Never return Markdown. AI output is a draft for user review, not a final todo.

        Source text:
        \(input.sourceText)
        \(userNoteLine)\(preferredPresetLine)\(revisionInstructionLine)\(maximumOutputLine)\(captureContext)

        Available categories:
        \(categoryLines)
        """
    }

    private static func captureContextLines(input: TaskDraftInput) -> String {
        var lines: [String] = []
        let isoFormatter = ISO8601DateFormatter()
        if let captureCreatedAt = input.captureCreatedAt {
            lines.append("captureCreatedAt: \(isoFormatter.string(from: captureCreatedAt))")
        }
        if let timeZoneIdentifier = input.timeZoneIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timeZoneIdentifier.isEmpty {
            lines.append("userTimeZone: \(timeZoneIdentifier)")
        }
        guard !lines.isEmpty else { return "" }
        return "\n\nCapture context:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}

public enum CLIProviderError: Error, Equatable, Sendable {
    case timedOut(providerId: String, providerName: String, timeoutSeconds: TimeInterval)
    case nonZeroExit(providerId: String, providerName: String, exitCode: Int32, stderr: String)
    case invalidJSON(providerId: String, providerName: String)

    public var userReadableMessage: String {
        switch self {
        case .timedOut(_, let providerName, let timeoutSeconds):
            return "\(providerName) timed out after \(formatSeconds(timeoutSeconds)) seconds."
        case .nonZeroExit(_, let providerName, let exitCode, let stderr):
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStderr.isEmpty {
                return "\(providerName) exited with code \(exitCode)."
            }
            return "\(providerName) exited with code \(exitCode): \(trimmedStderr)"
        case .invalidJSON(_, let providerName):
            return "\(providerName) returned invalid draft JSON."
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds.rounded() == seconds {
            return String(Int(seconds))
        }
        return String(format: "%.1f", seconds)
    }
}

public enum CLIStrictDraftParser {
    public static func parseResult(
        _ result: CLIDraftCommandResult,
        captureItemId: UUID,
        provider: CLIDraftProviderDescriptor,
        generatedAt: Date = Date()
    ) throws -> ProcessingDraft {
        if result.timedOut {
            throw CLIProviderError.timedOut(
                providerId: provider.id,
                providerName: provider.displayName,
                timeoutSeconds: provider.defaultTimeoutSeconds
            )
        }

        guard result.exitCode == 0 else {
            throw CLIProviderError.nonZeroExit(
                providerId: provider.id,
                providerName: provider.displayName,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return try parseStdout(
            result.stdout,
            captureItemId: captureItemId,
            provider: provider,
            generatedAt: generatedAt
        )
    }

    public static func parseStdout(
        _ stdout: String,
        captureItemId: UUID,
        provider: CLIDraftProviderDescriptor,
        generatedAt: Date = Date()
    ) throws -> ProcessingDraft {
        do {
            return try TaskDraftParser.parse(
                stdout,
                captureItemId: captureItemId,
                generatedByProvider: provider.id,
                generatedAt: generatedAt
            )
        } catch {
            throw CLIProviderError.invalidJSON(providerId: provider.id, providerName: provider.displayName)
        }
    }
}
