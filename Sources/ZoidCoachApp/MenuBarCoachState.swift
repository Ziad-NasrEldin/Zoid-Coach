import Foundation
import ZoidCoachCore

enum MenuBarCoachTone: Equatable {
    case neutral
    case active
    case paused
    case coachingPaused
    case attention

    var symbol: String {
        switch self {
        case .neutral: "circle.dotted"
        case .active: "play.fill"
        case .paused: "pause.fill"
        case .coachingPaused: "pause.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .neutral: "Zoid 666 is ready"
        case .active: "A task is active"
        case .paused: "A task is paused"
        case .coachingPaused: "Coaching is paused"
        case .attention: "A source needs attention"
        }
    }
}

enum MenuBarTaskAction: String, Hashable, Identifiable {
    case start
    case pause
    case resume
    case endBreak
    case startBreak
    case complete
    case markBlocked
    case switchTask
    case openToday
    case endWorkday

    var id: String { rawValue }

    var accessibilityLabel: String {
        accessibilityLabel(locale: .current)
    }

    func accessibilityLabel(locale: Locale) -> String {
        switch self {
        case .start: "Start recommended task"
        case .pause: "Pause active task"
        case .resume: "Resume paused task"
        case .endBreak: "End break and resume task"
        case .startBreak:
            "Start a break lasting \(LocaleAwareDurationFormatter(locale: locale).wide(minutes: 15))"
        case .complete: "Complete active task"
        case .markBlocked: "Mark task as blocked"
        case .switchTask: "Switch to another task"
        case .openToday: "Open Today"
        case .endWorkday: "End the workday"
        }
    }
}

struct MenuBarCoachState: Equatable {
    let snapshot: TodaySnapshot?
    let locale: Locale
    let tone: MenuBarCoachTone
    let activeTask: TodayTaskRow?
    let pausedTask: TodayTaskRow?
    let blockedTask: TodayTaskRow?
    let recommendedTask: TodayTaskRow?
    let attentionDetail: String?
    let coachingIsPaused: Bool
    let unresolvedPromptCount: Int
    let notificationFallbackIsActive: Bool
    let snapshotConfirmedAt: Date?

    init(
        snapshot: TodaySnapshot?,
        snapshotConfirmedAt: Date? = nil,
        locale: Locale = .current,
        coachingIsPaused: Bool = false,
        unresolvedPromptCount: Int = 0,
        notificationsUnavailable: Bool = false
    ) {
        self.snapshot = snapshot
        self.snapshotConfirmedAt = snapshotConfirmedAt
        self.locale = locale
        self.coachingIsPaused = coachingIsPaused
        self.unresolvedPromptCount = max(0, unresolvedPromptCount)
        notificationFallbackIsActive = notificationsUnavailable && unresolvedPromptCount > 0
        let rows = snapshot?.taskRows ?? []
        activeTask = snapshot?.activeTask.flatMap { active in
            rows.first { $0.taskID == active.taskID }
        } ?? rows.first { $0.state == .active }
        pausedTask = rows.first { $0.state == .paused }
        blockedTask = rows.first { $0.state == .blocked }
        recommendedTask = snapshot?.recommendation.taskID.flatMap { taskID in
            rows.first { $0.taskID == taskID && $0.state == .ready }
        } ?? rows.first { $0.state == .ready && $0.isOptional != true }

        let unhealthy = (snapshot?.sources ?? []).first { source in
            !Self.healthySourceStates.contains(Self.normalized(source.state))
        }
        attentionDetail = unhealthy.map { "\($0.sourceID): \($0.detail)" }

        if coachingIsPaused {
            tone = .coachingPaused
        } else if activeTask != nil {
            tone = .active
        } else if pausedTask != nil {
            tone = .paused
        } else if blockedTask != nil {
            tone = .attention
        } else if unhealthy != nil {
            tone = .attention
        } else {
            tone = .neutral
        }
    }

    var primaryTask: TodayTaskRow? { activeTask ?? pausedTask ?? blockedTask ?? recommendedTask }

    var menuBarSymbol: String {
        notificationFallbackIsActive ? "exclamationmark.bubble.fill" : tone.symbol
    }

    var menuBarLabel: String {
        guard notificationFallbackIsActive else { return tone.label }
        return unresolvedPromptCount == 1
            ? "One decision is waiting in Today"
            : "\(unresolvedPromptCount) decisions are waiting in Today"
    }

    var notificationFallbackDetail: String? {
        guard notificationFallbackIsActive else { return nil }
        let decision = unresolvedPromptCount == 1 ? "decision" : "decisions"
        return "Notifications are unavailable. \(unresolvedPromptCount) \(decision) waiting in Today. Task controls remain available here."
    }

    var canStartBreak: Bool { activeTask != nil }

    var canEndWorkday: Bool { activeTask != nil }

    var switchCandidates: [TodayTaskRow] {
        guard activeTask != nil else { return [] }
        return (snapshot?.taskRows ?? []).filter { row in
            row.state == .ready && row.isOptional != true
        }
    }

    var availableTaskActions: [MenuBarTaskAction] {
        if activeTask != nil {
            var actions: [MenuBarTaskAction] = [.pause, .startBreak, .complete, .markBlocked]
            if !switchCandidates.isEmpty {
                actions.append(.switchTask)
            }
            actions.append(contentsOf: [.openToday, .endWorkday])
            return actions
        }
        if let pausedTask {
            return [pausedTask.acceptedBreak == nil ? .resume : .endBreak, .markBlocked, .openToday]
        }
        if blockedTask != nil {
            return [.openToday]
        }
        if recommendedTask != nil {
            return [.start, .markBlocked, .openToday]
        }
        return [.openToday]
    }

    var workdayHasEnded: Bool { pausedTask?.latestPauseReason == .endingWorkday }

    var activeCommitment: ActiveCommitmentPresentation? {
        activeTask.flatMap { ActiveCommitmentPresentation(task: $0) }
    }

    func activeTimeComparison(at date: Date) -> MenuBarActiveTimeComparison? {
        guard let activeTask,
              let comparison = activeTask.activeTimeComparison
        else { return nil }
        return MenuBarActiveTimeComparison(
            elapsedMinutes: liveElapsedMinutes(for: activeTask, at: date),
            observedAlignedMinutes: comparison.observedAlignedMinutes,
            evidenceExplanation: comparison.evidenceExplanation,
            locale: locale
        )
    }

    var compactTaskFacts: [String] {
        guard let task = primaryTask else { return [] }
        let duration = LocaleAwareDurationFormatter(locale: locale)
        var facts: [String] = []
        if task.isMainObjective { facts.append("Main objective") }
        facts.append("\(duration.compact(minutes: task.estimateMinutes)) estimate")
        facts.append("\(task.urgency.rawValue.capitalized) urgency")
        if let dueDate = task.dueDate {
            facts.append("Due \(dueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
        }
        if task.isLocked { facts.append("Locked") }
        if let blockedReason = task.blockedReason {
            facts.append("Blocked: \(blockedReason)")
        }
        return facts
    }

    func compactTaskAccessibilitySummary(at date: Date) -> String? {
        guard let task = primaryTask else { return nil }
        return ([task.title, taskStatus(at: date)] + compactTaskFacts).joined(separator: ". ")
    }

    var taskStatus: String { taskStatus(at: Date()) }

    func taskStatus(at date: Date) -> String {
        let duration = LocaleAwareDurationFormatter(locale: locale)
        if let activeTask {
            let elapsedMinutes = liveElapsedMinutes(for: activeTask, at: date)
            guard let commitment = ActiveCommitmentPresentation(task: activeTask, at: date) else {
                return "Active · \(duration.compact(minutes: elapsedMinutes)) tracked"
            }
            switch commitment.timingMode {
            case .openEnded:
                return "Active · Open-ended · \(duration.compact(minutes: elapsedMinutes)) tracked"
            case let .bounded(_, remainingMinutes):
                return "Active sprint · \(duration.compact(minutes: remainingMinutes)) left · \(duration.compact(minutes: elapsedMinutes)) tracked"
            case .continuedOpenEnded:
                return "Active · Open-ended continuation · \(duration.compact(minutes: elapsedMinutes)) tracked"
            case .sprintComplete:
                return "Sprint complete · Task remains active"
            }
        }
        if let pausedTask {
            if let acceptedBreak = pausedTask.acceptedBreak {
                let remaining = acceptedBreak.remainingSeconds(at: date)
                if remaining == 0 {
                    return "Accepted break ended · Resume when ready"
                }
                return "Accepted break · \(duration.compact(minutes: (remaining + 59) / 60)) left"
            }
            if workdayHasEnded {
                return "Workday ended · Tracked time is saved"
            }
            return pausedTask.latestPauseReason?.userFacingLabel ?? "Paused"
        }
        if let blockedTask {
            return blockedTask.blockedReason.map { "Blocked: \($0)" } ?? "Blocked"
        }
        if recommendedTask != nil {
            return "Recommended next"
        }
        return "No active task"
    }

    private func liveElapsedMinutes(for task: TodayTaskRow, at date: Date) -> Int {
        guard let startedAt = snapshot?.activeTask?.startedAt,
              snapshot?.activeTask?.taskID == task.taskID,
              let snapshotConfirmedAt
        else {
            return task.elapsedMinutes
        }
        let segmentAtConfirmation = max(0, Int(snapshotConfirmedAt.timeIntervalSince(startedAt) / 60))
        let elapsedBeforeOpenInterval = max(0, task.elapsedMinutes - segmentAtConfirmation)
        let currentOpenInterval = max(0, Int(date.timeIntervalSince(startedAt) / 60))
        return max(task.elapsedMinutes, elapsedBeforeOpenInterval + currentOpenInterval)
    }

    private static let healthySourceStates: Set<String> = [
        "healthy", "connected", "running", "ready"
    ]

    private static func normalized(_ state: String) -> String {
        state.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}

struct MenuBarActiveTimeComparison: Equatable {
    let elapsedMinutes: Int
    let observedAlignedMinutes: Int
    let evidenceExplanation: String
    let locale: Locale

    init(
        elapsedMinutes: Int,
        observedAlignedMinutes: Int,
        evidenceExplanation: String,
        locale: Locale = .current
    ) {
        self.elapsedMinutes = max(0, elapsedMinutes)
        self.observedAlignedMinutes = max(0, observedAlignedMinutes)
        self.evidenceExplanation = evidenceExplanation
        self.locale = locale
    }

    var elapsedText: String { "\(compactDuration(elapsedMinutes)) ELAPSED" }
    var alignedText: String { "\(compactDuration(observedAlignedMinutes)) OBSERVED ALIGNED" }
    var elapsedAccessibilityText: String { "Task elapsed, \(duration.wide(minutes: elapsedMinutes))" }
    var alignedAccessibilityText: String { "Observed aligned, \(duration.wide(minutes: observedAlignedMinutes))" }

    var accessibilitySummary: String {
        "Task elapsed \(duration.wide(minutes: elapsedMinutes)). Observed aligned \(duration.wide(minutes: observedAlignedMinutes)). \(evidenceExplanation)"
    }

    private var duration: LocaleAwareDurationFormatter {
        LocaleAwareDurationFormatter(locale: locale)
    }

    private func compactDuration(_ minutes: Int) -> String {
        duration.compact(minutes: minutes).uppercased(with: locale)
    }
}
