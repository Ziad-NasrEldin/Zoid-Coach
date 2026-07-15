import Foundation
import ZoidCoachCore

public enum PromptResponseEffect: Equatable, Sendable {
    case none
    case meetingEnqueued(commandID: String, wasInserted: Bool)
    case meetingIgnored(candidateID: String)
    case meetingEditRequested(candidateID: String)
    case planUndoQueued(dayKey: String)
    case planScheduleQueued(dayKey: String)
    case planningSnoozed(until: Date, promptID: String)
    case planningDismissed(until: Date, promptID: String)
    case unplannedDaySelected
    case coachingTaskStarted(taskID: String)
    case coachingSprintStarted(taskID: String, durationMinutes: Int)
    case coachingTaskPaused(taskID: String)
    case coachingWorkdayEnded(taskID: String)
    case coachingBreakStarted(taskID: String)
    case ambiguousActivityClassified(
        promptID: String,
        classification: BehaviorClassification,
        taskID: String?
    )
    case ambiguousActivityKeptUnknown(promptID: String)
}

public final class PromptResponseEffectRouter: @unchecked Sendable {
    private let outbox: ActionOutboxStore
    private let meetingArchive: ScreenwatchArchive
    private let planUndoRequests: PlanUndoRequestStore?
    private let planScheduleRequests: PlanScheduleRequestStore?
    private let promptStore: PromptInboxStore?
    private let planningInvitations: PlanningInvitationService?
    private let taskExecution: TaskExecutionStore?
    private let ambiguousActivityPrompts: AmbiguousActivityPromptService?
    private let schedulingCalendarIdentifier: @Sendable () throws -> String?

    public init(
        outbox: ActionOutboxStore,
        meetingArchive: ScreenwatchArchive,
        planUndoRequests: PlanUndoRequestStore? = nil,
        planScheduleRequests: PlanScheduleRequestStore? = nil,
        promptStore: PromptInboxStore? = nil,
        planningInvitations: PlanningInvitationService? = nil,
        taskExecution: TaskExecutionStore? = nil,
        ambiguousActivityPrompts: AmbiguousActivityPromptService? = nil,
        schedulingCalendarIdentifier: @escaping @Sendable () throws -> String? = { nil }
    ) {
        self.outbox = outbox
        self.meetingArchive = meetingArchive
        self.planUndoRequests = planUndoRequests
        self.planScheduleRequests = planScheduleRequests
        self.promptStore = promptStore
        self.planningInvitations = planningInvitations
        self.taskExecution = taskExecution
        self.ambiguousActivityPrompts = ambiguousActivityPrompts
        self.schedulingCalendarIdentifier = schedulingCalendarIdentifier
    }

    public func apply(_ result: PromptResponseResult) throws -> PromptResponseEffect {
        let effect = try applyEffect(result)
        try promptStore?.markEffectApplied(responseID: result.response.id)
        return effect
    }

    private func applyEffect(_ result: PromptResponseResult) throws -> PromptResponseEffect {
        if let ambiguousActivityPrompts {
            switch try ambiguousActivityPrompts.apply(result) {
            case .none:
                break
            case let .classified(promptID, classification, taskID):
                return .ambiguousActivityClassified(
                    promptID: promptID,
                    classification: classification,
                    taskID: taskID
                )
            case let .keptUnknown(promptID):
                return .ambiguousActivityKeptUnknown(promptID: promptID)
            }
        }
        if result.wasApplied, let taskExecution {
            let payloadTaskID = result.episode.payload["taskID"]
            switch result.response.action {
            case .startRecommendedTask:
                guard let taskID = payloadTaskID else { break }
                try taskExecution.apply(.start, taskID: taskID, at: result.response.respondedAt)
                return .coachingTaskStarted(taskID: taskID)
            case .startShortSprint:
                guard let taskID = payloadTaskID else { break }
                try taskExecution.apply(.startSprint10, taskID: taskID, at: result.response.respondedAt)
                return .coachingSprintStarted(taskID: taskID, durationMinutes: 10)
            case .startWorkSprint:
                guard let taskID = payloadTaskID else { break }
                try taskExecution.apply(.startSprint20, taskID: taskID, at: result.response.respondedAt)
                return .coachingSprintStarted(taskID: taskID, durationMinutes: 20)
            case .returnToActiveTask:
                guard let taskID = payloadTaskID else { break }
                let state = try taskExecution.snapshot(for: [taskID], now: result.response.respondedAt)[taskID]?.state
                try taskExecution.apply(state == .paused ? .resume : .start, taskID: taskID, at: result.response.respondedAt)
                return .coachingTaskStarted(taskID: taskID)
            case .pauseTask:
                guard let taskID = try taskExecution.activeTask(now: result.response.respondedAt)?.taskID else { break }
                try taskExecution.apply(.pause, taskID: taskID, at: result.response.respondedAt)
                return .coachingTaskPaused(taskID: taskID)
            case .endWorkday:
                guard let taskID = try taskExecution.activeTask(now: result.response.respondedAt)?.taskID else { break }
                try taskExecution.apply(.pauseForEndOfDay, taskID: taskID, at: result.response.respondedAt)
                return .coachingWorkdayEnded(taskID: taskID)
            default:
                break
            }
        }
        if result.episode.type == PromptNotificationCategory.gamingDrift.rawValue,
           result.response.action == .startBreak,
           result.wasApplied,
           let taskExecution,
           let activeTaskID = try taskExecution.activeTask(now: result.response.respondedAt)?.taskID {
            try taskExecution.apply(.pauseForBreak, taskID: activeTaskID, at: result.response.respondedAt)
            return .coachingBreakStarted(taskID: activeTaskID)
        }
        if let planningInvitations {
            switch try planningInvitations.apply(result) {
            case .none:
                break
            case let .snoozed(until, promptID):
                return .planningSnoozed(until: until, promptID: promptID)
            case let .dismissed(until, promptID):
                return .planningDismissed(until: until, promptID: promptID)
            case .unplanned:
                return .unplannedDaySelected
            }
        }
        if result.episode.type == "PLAN_READY",
           result.response.action == .acceptPlan,
           let dayKey = result.episode.payload["localDay"],
           let planScheduleRequests {
            try planScheduleRequests.enqueue(promptID: result.episode.id, dayKey: dayKey)
            return result.wasApplied ? .planScheduleQueued(dayKey: dayKey) : .none
        }
        if result.episode.type == "PLAN_CHANGED",
           result.response.action == .undoPlanChange,
           let dayKey = result.episode.payload["day"],
           let planUndoRequests {
            try planUndoRequests.enqueue(promptID: result.episode.id, dayKey: dayKey)
            return result.wasApplied ? .planUndoQueued(dayKey: dayKey) : .none
        }
        guard result.episode.type == "MEETING_CANDIDATE",
              let candidateID = result.episode.payload["candidateID"],
              let candidate = try meetingArchive.meetingCandidate(id: candidateID)
        else { return .none }
        switch result.response.action {
        case .addMeeting:
            let semanticCandidate = MeetingCandidate(
                title: candidate.title,
                start: candidate.start,
                durationMinutes: candidate.durationMinutes,
                confidence: candidate.confidence,
                requiresClarification: candidate.requiresClarification,
                sourceText: "",
                confidenceScore: candidate.confidenceScore,
                participants: candidate.participants,
                location: candidate.location,
                callLink: candidate.callLink,
                timezoneIdentifier: candidate.timezoneIdentifier
            )
            let fingerprint = MeetingCandidatePolicy().fingerprint(semanticCandidate)
            let enqueued = try outbox.enqueue(
                type: .createConfirmedMeeting,
                entityID: candidate.id,
                desiredState: .meeting(MeetingDesiredState(
                    title: candidate.title,
                    start: candidate.start,
                    durationMinutes: candidate.durationMinutes,
                    calendarIdentifier: try schedulingCalendarIdentifier(),
                    candidateFingerprint: fingerprint,
                    participants: candidate.participants,
                    location: candidate.location,
                    callLink: candidate.callLink,
                    timezoneIdentifier: candidate.timezoneIdentifier
                )),
                planVersion: 1
            )
            if candidate.state != "accepted", candidate.state != "scheduled" {
                try meetingArchive.updateMeetingCandidate(candidate, state: "accepted")
            }
            return result.wasApplied
                ? .meetingEnqueued(commandID: enqueued.command.id, wasInserted: enqueued.wasInserted)
                : .none
        case .ignore:
            try meetingArchive.updateMeetingCandidate(candidate, state: "ignored")
            return result.wasApplied ? .meetingIgnored(candidateID: candidate.id) : .none
        case .editMeeting:
            try meetingArchive.updateMeetingCandidate(candidate, state: "edit_requested")
            return result.wasApplied ? .meetingEditRequested(candidateID: candidate.id) : .none
        default:
            return .none
        }
    }
}
