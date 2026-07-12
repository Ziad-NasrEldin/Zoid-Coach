import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func meetingCandidateCardDoesNotRenderRawConversationEvidence() {
    let rawOCR = """
    Chats
    Unread 2
    Sarah: Roadmap review tomorrow at 3 pm
    Omar: Confirmed
    """
    let candidate = StoredMeetingCandidate(
        sourceDay: "2026-07-10",
        epoch: 1_783_667_605,
        title: "Roadmap review",
        start: Date(timeIntervalSince1970: 1_783_667_605),
        durationMinutes: 30,
        confidence: .high,
        requiresClarification: false,
        state: "ready_for_confirmation",
        participants: ["Sarah", "Omar"],
        callLink: "https://meet.example/roadmap",
        timezoneIdentifier: "Africa/Cairo",
        sourceEvidence: rawOCR
    )

    let context = MeetingCandidateCardContext.text(for: candidate)

    #expect(!context.contains(rawOCR))
    #expect(!context.contains("Unread 2"))
    #expect(context.contains("Source: WhatsApp"))
    #expect(context.contains("Encrypted conversation evidence is available in Zoid 666"))
}
