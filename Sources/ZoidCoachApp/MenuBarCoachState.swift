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

struct MenuBarCoachState: Equatable {
    let snapshot: TodaySnapshot?
    let tone: MenuBarCoachTone
    let activeTask: TodayTaskRow?
    let pausedTask: TodayTaskRow?
    let recommendedTask: TodayTaskRow?
    let attentionDetail: String?
    let coachingIsPaused: Bool
    let unresolvedPromptCount: Int
    let notificationFallbackIsActive: Bool

    init(
        snapshot: TodaySnapshot?,
        coachingIsPaused: Bool = false,
        unresolvedPromptCount: Int = 0,
        notificationsUnavailable: Bool = false
    ) {
        self.snapshot = snapshot
        self.coachingIsPaused = coachingIsPaused
        self.unresolvedPromptCount = max(0, unresolvedPromptCount)
        notificationFallbackIsActive = notificationsUnavailable && unresolvedPromptCount > 0
        let rows = snapshot?.taskRows ?? []
        activeTask = snapshot?.activeTask.flatMap { active in
            rows.first { $0.taskID == active.taskID }
        } ?? rows.first { $0.state == .active }
        pausedTask = rows.first { $0.state == .paused }
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
        } else if unhealthy != nil {
            tone = .attention
        } else {
            tone = .neutral
        }
    }

    var primaryTask: TodayTaskRow? { activeTask ?? pausedTask ?? recommendedTask }

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

    var workdayHasEnded: Bool { pausedTask?.latestPauseReason == .endingWorkday }

    var taskStatus: String { taskStatus(at: Date()) }

    func taskStatus(at date: Date) -> String {
        if let activeTask {
            if let sprint = activeTask.sprint, sprint.state == .active {
                return "Focus sprint · \(max(0, sprint.remainingSeconds / 60)) min left"
            }
            return "Active · \(activeTask.elapsedMinutes) min tracked"
        }
        if let pausedTask {
            if let acceptedBreak = pausedTask.acceptedBreak {
                let remaining = acceptedBreak.remainingSeconds(at: date)
                if remaining == 0 {
                    return "Accepted break ended · Resume when ready"
                }
                return "Accepted break · \((remaining + 59) / 60) min left"
            }
            if workdayHasEnded {
                return "Workday ended · Tracked time is saved"
            }
            return pausedTask.latestPauseReason?.userFacingLabel ?? "Paused"
        }
        if recommendedTask != nil {
            return "Recommended next"
        }
        return "No active task"
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
