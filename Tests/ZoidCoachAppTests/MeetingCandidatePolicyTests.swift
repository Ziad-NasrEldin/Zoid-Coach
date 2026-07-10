import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func meetingPolicySuppressesLikelyDuplicateBeforeConflictRouting() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = MeetingCandidate(
        title: "Client proposal review",
        start: start,
        durationMinutes: 30,
        confidence: .high,
        requiresClarification: false,
        sourceText: "Tuesday 3pm",
        participants: ["Sarah"],
        startExpression: "Tuesday 3pm"
    )
    let event = ExistingMeetingEvent(id: "event", title: "Proposal review", start: start.addingTimeInterval(5 * 60), end: start.addingTimeInterval(35 * 60), participants: ["Sarah"])

    #expect(MeetingCandidatePolicy().route(candidate, existingEvents: [event]) == .duplicate(existingEventID: "event"))
}

@Test
func meetingPolicyRoutesOverlapAsConflictAndLowConfidenceWithoutInterruption() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = MeetingCandidate(title: "Meeting detected", start: start, durationMinutes: 30, confidence: .high, requiresClarification: false, sourceText: "tomorrow 3pm")
    let conflict = ExistingMeetingEvent(id: "busy", title: "Doctor", start: start.addingTimeInterval(-300), end: start.addingTimeInterval(900))
    let low = MeetingCandidate(title: "Maybe", start: start.addingTimeInterval(3_600), durationMinutes: 30, confidence: .low, requiresClarification: false, sourceText: "maybe", confidenceScore: 0.4)

    #expect(MeetingCandidatePolicy().route(candidate, existingEvents: [conflict]) == .conflict(existingEventID: "busy"))
    #expect(MeetingCandidatePolicy().route(low, existingEvents: []) == .lowConfidence)
    #expect(MeetingCandidatePolicy().fingerprint(candidate) == MeetingCandidatePolicy().fingerprint(candidate))
}

@Test
func meetingPolicyRequiresTimeProximityAndTitleOrParticipantEvidenceForDuplicate() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = MeetingCandidate(
        title: "Roadmap review",
        start: start,
        durationMinutes: 30,
        confidence: .high,
        requiresClarification: false,
        sourceText: "",
        participants: ["Alex"]
    )
    let participantMatch = ExistingMeetingEvent(
        id: "participant",
        title: "Weekly sync",
        start: start.addingTimeInterval(120),
        end: start.addingTimeInterval(1_800),
        participants: ["Alex"]
    )
    let unrelated = ExistingMeetingEvent(
        id: "unrelated",
        title: "Dentist",
        start: start,
        end: start.addingTimeInterval(1_800),
        participants: ["Sam"]
    )
    let tooFarAway = ExistingMeetingEvent(
        id: "far",
        title: "Roadmap review",
        start: start.addingTimeInterval(3_600),
        end: start.addingTimeInterval(5_400),
        participants: ["Alex"]
    )

    #expect(MeetingCandidatePolicy().route(candidate, existingEvents: [participantMatch]) == .duplicate(existingEventID: "participant"))
    #expect(MeetingCandidatePolicy().route(candidate, existingEvents: [unrelated]) == .conflict(existingEventID: "unrelated"))
    #expect(MeetingCandidatePolicy().route(candidate, existingEvents: [tooFarAway]) == .readyForConfirmation)
}
