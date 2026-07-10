import Foundation
import ZoidCoachCore

public enum PromptResponseEffect: Equatable, Sendable {
    case none
    case meetingEnqueued(commandID: String, wasInserted: Bool)
    case meetingIgnored(candidateID: String)
    case planUndoQueued(dayKey: String)
}

public final class PromptResponseEffectRouter: @unchecked Sendable {
    private let outbox: ActionOutboxStore
    private let meetingArchive: ScreenwatchArchive
    private let planUndoRequests: PlanUndoRequestStore?

    public init(outbox: ActionOutboxStore, meetingArchive: ScreenwatchArchive, planUndoRequests: PlanUndoRequestStore? = nil) {
        self.outbox = outbox
        self.meetingArchive = meetingArchive
        self.planUndoRequests = planUndoRequests
    }

    public func apply(_ result: PromptResponseResult) throws -> PromptResponseEffect {
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
                sourceText: ""
            )
            let fingerprint = MeetingCandidatePolicy().fingerprint(semanticCandidate)
            let enqueued = try outbox.enqueue(
                type: .createConfirmedMeeting,
                entityID: candidate.id,
                desiredState: .meeting(MeetingDesiredState(
                    title: candidate.title,
                    start: candidate.start,
                    durationMinutes: candidate.durationMinutes,
                    calendarIdentifier: nil,
                    candidateFingerprint: fingerprint
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
            return .none
        default:
            return .none
        }
    }
}
