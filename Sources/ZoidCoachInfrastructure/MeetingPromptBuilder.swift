import Foundation
import ZoidCoachCore

public enum MeetingCalendarAssessment: Equatable, Sendable {
    case clear
    case conflict(ExistingMeetingEvent)
    case duplicate(ExistingMeetingEvent)
}

public enum MeetingPromptBuilder {
    public static func candidatesRequiringPromptWork(
        _ candidates: [StoredMeetingCandidate],
        unresolvedPrompts: [PromptEpisode],
        limit: Int = 12
    ) -> [StoredMeetingCandidate] {
        let promptByCandidateID = Dictionary(
            uniqueKeysWithValues: unresolvedPrompts.compactMap { episode in
                episode.type == "MEETING_CANDIDATE"
                    ? episode.payload["candidateID"].map { ($0, episode) }
                    : nil
            }
        )
        return Array(candidates.lazy.filter { candidate in
            candidate.state != "edit_requested" && promptByCandidateID[candidate.id]?.state != .presented
        }.prefix(max(0, limit)))
    }

    public static func drafts(
        for candidates: [StoredMeetingCandidate],
        calendarDestination: String,
        assessment: (StoredMeetingCandidate) -> MeetingCalendarAssessment
    ) -> [PromptDraft] {
        candidates.map {
            draft(for: $0, calendarDestination: calendarDestination, assessment: assessment($0))
        }
    }

    public static func draft(
        for candidate: StoredMeetingCandidate,
        calendarDestination: String,
        assessment: MeetingCalendarAssessment
    ) -> PromptDraft {
        let participants = candidate.participants.isEmpty ? "Unknown participants" : candidate.participants.joined(separator: ", ")
        let location = candidate.location ?? "No location"
        let callLink = candidate.callLink ?? "No call link"
        let evidence = candidate.sourceEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Conversation evidence unavailable"
            : "Encrypted conversation evidence is available in Zoid 666"
        var details = [
            "Who: \(participants)",
            "When: \(candidate.start.formatted(date: .abbreviated, time: .shortened)) for \(candidate.durationMinutes) minutes (\(candidate.timezoneIdentifier))",
            "Where: \(location)",
            "Link: \(callLink)",
            "Calendar: \(calendarDestination)",
            "Source: \(evidence)"
        ]
        var payload = [
            "candidateID": candidate.id,
            "title": candidate.title,
            "start": ISO8601DateFormatter().string(from: candidate.start),
            "durationMinutes": String(candidate.durationMinutes),
            "participants": participants,
            "calendarDestination": calendarDestination,
            "location": location,
            "callLink": callLink,
            "timezoneIdentifier": candidate.timezoneIdentifier
        ]
        switch assessment {
        case .clear:
            details.append("Conflict: None found")
        case let .conflict(event):
            details.append("Conflict: \(event.title), \(event.start.formatted(date: .abbreviated, time: .shortened))")
            payload["matchedEventID"] = event.id
            payload["matchedEventTitle"] = event.title
            payload["calendarAssessment"] = "conflict"
        case let .duplicate(event):
            details.append("Possible duplicate: \(event.title), \(event.start.formatted(date: .abbreviated, time: .shortened))")
            payload["matchedEventID"] = event.id
            payload["matchedEventTitle"] = event.title
            payload["calendarAssessment"] = "duplicate"
        }
        return PromptDraft(
            decisionKey: "meeting:\(candidate.id)",
            type: "MEETING_CANDIDATE",
            title: candidate.title,
            summary: details.joined(separator: "\n"),
            actions: [
                PromptAction(kind: .addMeeting, title: "Add", role: .primary, requiresConfirmation: true),
                PromptAction(kind: .editMeeting, title: "Edit"),
                PromptAction(kind: .ignore, title: "Ignore")
            ],
            payload: payload,
            expiresAt: candidate.start
        )
    }
}
