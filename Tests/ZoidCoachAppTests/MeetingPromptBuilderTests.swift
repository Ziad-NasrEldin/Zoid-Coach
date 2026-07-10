import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func meetingPromptIncludesDecisionEvidenceAndCalendarContext() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = StoredMeetingCandidate(
        sourceDay: "2027-01-15",
        epoch: 1_800_000_000,
        title: "Roadmap review",
        start: start,
        durationMinutes: 45,
        confidence: .high,
        requiresClarification: false,
        state: "ready_for_confirmation",
        confidenceScore: 0.94,
        participants: ["Sarah", "Omar"],
        location: "Maadi office",
        callLink: "https://meet.example/roadmap",
        timezoneIdentifier: "Africa/Cairo",
        sourceEvidence: "Sarah: Roadmap review tomorrow at 3 pm? Omar: Confirmed."
    )
    let matchedEvent = ExistingMeetingEvent(
        id: "event-42",
        title: "Product review",
        start: start.addingTimeInterval(-300),
        end: start.addingTimeInterval(1_800),
        participants: ["Sarah"]
    )

    let draft = MeetingPromptBuilder.draft(
        for: candidate,
        calendarDestination: "Work",
        assessment: .conflict(matchedEvent)
    )

    #expect(draft.summary.contains("Sarah, Omar"))
    #expect(draft.summary.contains("Maadi office"))
    #expect(draft.summary.contains("https://meet.example/roadmap"))
    #expect(draft.summary.contains("Africa/Cairo"))
    #expect(draft.summary.contains("Encrypted conversation evidence is available in Zoid Coach"))
    #expect(draft.payload["sourceEvidence"] == nil)
    #expect(draft.summary.contains("Work"))
    #expect(draft.summary.contains("Product review"))
    #expect(draft.payload["matchedEventID"] == "event-42")
    #expect(draft.payload["calendarDestination"] == "Work")
}

@Test
func meetingPromptBuilderProducesOneDraftForEveryUnresolvedCandidate() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let candidates = [0, 1].map { offset in
        StoredMeetingCandidate(
            sourceDay: "2027-01-15",
            epoch: 1_800_000_000 + offset,
            title: "Meeting \(offset)",
            start: start.addingTimeInterval(TimeInterval(offset * 3_600)),
            durationMinutes: 30,
            confidence: .high,
            requiresClarification: false,
            state: "ready_for_confirmation"
        )
    }

    let drafts = MeetingPromptBuilder.drafts(
        for: candidates,
        calendarDestination: "Work",
        assessment: { _ in .clear }
    )

    #expect(drafts.map(\.decisionKey) == candidates.map { "meeting:\($0.id)" })
}

@Test
func meetingPromptBatchDoesNotLetPresentedCandidatesStarveNewCandidates() {
    let start = Date(timeIntervalSince1970: 1_900_000_000)
    let candidates = (0..<14).map { offset in
        StoredMeetingCandidate(
            sourceDay: "2030-03-17",
            epoch: 1_900_000_000 + offset,
            title: "Meeting \(offset)",
            start: start.addingTimeInterval(TimeInterval(offset * 60)),
            durationMinutes: 30,
            confidence: .high,
            requiresClarification: false,
            state: "ready_for_confirmation"
        )
    }
    let presented = candidates.prefix(12).enumerated().map { index, candidate in
        PromptEpisode(
            id: "prompt-\(index)",
            decisionKey: "meeting:\(candidate.id)",
            type: "MEETING_CANDIDATE",
            state: .presented,
            title: candidate.title,
            summary: "Presented",
            actions: [PromptAction(kind: .addMeeting, title: "Add")],
            payload: ["candidateID": candidate.id],
            createdAt: start
        )
    }

    let actionable = MeetingPromptBuilder.candidatesRequiringPromptWork(
        candidates,
        unresolvedPrompts: presented
    )

    #expect(actionable.map(\.id) == Array(candidates.suffix(2)).map(\.id))
}
