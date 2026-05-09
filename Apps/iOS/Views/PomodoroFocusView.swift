import Combine
import LisdoCore
import SwiftUI

struct PomodoroFocusView: View {
    var todo: Todo
    var categoryName: String
    var onClose: () -> Void
    var onCompleteTodo: () -> Void

    @State private var phase: PomodoroPhase = .focus
    @State private var remainingSeconds: TimeInterval = PomodoroPhase.focus.duration
    @State private var endDate: Date?
    @State private var isRunning = false
    @State private var completedFocusCount = 0
    @State private var statusText: String?
    @State private var didAutoStart = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height

            ZStack {
                LisdoTheme.surface.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    Group {
                        if isWide {
                            HStack(spacing: 34) {
                                timerDial
                                controlPanel
                            }
                        } else {
                            VStack(spacing: 30) {
                                timerDial
                                controlPanel
                            }
                        }
                    }
                    .padding(.horizontal, isWide ? 42 : 24)
                    .padding(.top, isWide ? 10 : 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            startTimer()
        }
        .onReceive(ticker) { now in
            guard isRunning, let endDate else { return }
            let remaining = endDate.timeIntervalSince(now)
            if remaining <= 0 {
                finishPhase()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(categoryName, systemImage: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                Text(todo.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(LisdoTheme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LisdoTheme.ink1)
            .accessibilityLabel("Close Pomodoro")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var timerDial: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(LisdoTheme.surface3, lineWidth: 18)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LisdoTheme.ink1,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)

                VStack(spacing: 10) {
                    Text(phase.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(LisdoTheme.ink3)
                    Text(Self.formatTime(currentRemainingSeconds))
                        .font(.system(size: 58, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LisdoTheme.ink1)
                        .minimumScaleFactor(0.72)
                    Text(isRunning ? "In focus" : "Paused")
                        .font(.system(size: 13))
                        .foregroundStyle(LisdoTheme.ink3)
                }
                .padding(24)
            }
            .frame(maxWidth: 360, maxHeight: 360)
            .aspectRatio(1, contentMode: .fit)

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else if let disabledText = LisdoPomodoroActivityController.disabledStatusText {
                Text(disabledText)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                Text("A quiet timer for this approved todo. The task stays in Lisdo and syncs through iCloud as a normal todo.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(LisdoTheme.ink3)
            }

            HStack(spacing: 10) {
                PomodoroMetric(title: "Focus", value: "\(completedFocusCount)")
                PomodoroMetric(title: "Mode", value: phase.shortLabel)
            }

            HStack(spacing: 10) {
                Button {
                    isRunning ? pauseTimer() : startTimer()
                } label: {
                    Label(isRunning ? "Pause" : "Resume", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PomodoroButtonStyle(filled: true))

                Button {
                    resetPhase()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PomodoroButtonStyle())
            }

            HStack(spacing: 10) {
                Button {
                    finishPhase()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PomodoroButtonStyle())

                Button {
                    completeTodo()
                } label: {
                    Label("Complete", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PomodoroButtonStyle())
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .lisdoCard(padding: 18)
    }

    private var currentRemainingSeconds: TimeInterval {
        guard isRunning, let endDate else {
            return remainingSeconds
        }
        return max(endDate.timeIntervalSinceNow, 0)
    }

    private var progress: Double {
        let elapsed = phase.duration - currentRemainingSeconds
        return min(max(elapsed / phase.duration, 0), 1)
    }

    private func startTimer() {
        let remaining = max(currentRemainingSeconds, 1)
        remainingSeconds = remaining
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        syncLiveActivity()
    }

    private func pauseTimer() {
        remainingSeconds = currentRemainingSeconds
        endDate = nil
        isRunning = false
        syncLiveActivity()
    }

    private func resetPhase() {
        remainingSeconds = phase.duration
        endDate = nil
        isRunning = false
        syncLiveActivity()
    }

    private func finishPhase() {
        if phase == .focus {
            completedFocusCount += 1
            phase = .shortBreak
        } else {
            phase = .focus
        }

        remainingSeconds = phase.duration
        endDate = nil
        isRunning = false
        startTimer()
    }

    private func completeTodo() {
        Task { @MainActor in
            await LisdoPomodoroActivityController.end(todoID: todo.id)
            onCompleteTodo()
        }
    }

    private func syncLiveActivity() {
        let remaining = currentRemainingSeconds
        let runningEndDate = isRunning ? endDate : nil
        Task { @MainActor in
            statusText = await LisdoPomodoroActivityController.startOrUpdate(
                todo: todo,
                categoryName: categoryName,
                phase: phase.displayName,
                endDate: runningEndDate,
                remainingSeconds: remaining,
                totalSeconds: phase.duration,
                isRunning: isRunning,
                completedFocusCount: completedFocusCount
            )
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private enum PomodoroPhase: Equatable {
    case focus
    case shortBreak

    var duration: TimeInterval {
        switch self {
        case .focus:
            return 25 * 60
        case .shortBreak:
            return 5 * 60
        }
    }

    var displayName: String {
        switch self {
        case .focus:
            return "Focus"
        case .shortBreak:
            return "Break"
        }
    }

    var shortLabel: String {
        switch self {
        case .focus:
            return "25m"
        case .shortBreak:
            return "5m"
        }
    }
}

private struct PomodoroMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(LisdoTheme.ink3)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PomodoroButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(filled ? LisdoTheme.onAccent : LisdoTheme.ink1)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(filled ? LisdoTheme.ink1 : LisdoTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(filled ? LisdoTheme.ink1 : LisdoTheme.divider, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
