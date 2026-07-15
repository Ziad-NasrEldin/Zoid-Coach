import Testing
@testable import ZoidCoachCore

@Test
func planningInvitationWithNoSuggestionsIsCalmOptionalAndNonBlocking() {
    let draft = PlanningInvitationPolicy.promptDraft(
        localDay: "2026-07-15",
        itemCount: 0,
        expiresAt: nil
    )

    #expect(draft.title == "Planning is available when you are ready")
    #expect(
        draft.summary
            == "You can make a small plan, or start without one. You can snooze or dismiss this invitation for now. Nothing is blocked."
    )
}

@Test
func planningInvitationNamesOneOrManySuggestionsWithoutMakingThemRequired() {
    let one = PlanningInvitationPolicy.promptDraft(
        localDay: "2026-07-15",
        itemCount: 1,
        expiresAt: nil
    )
    let many = PlanningInvitationPolicy.promptDraft(
        localDay: "2026-07-15",
        itemCount: 3,
        expiresAt: nil
    )

    #expect(
        one.summary
            == "You can review 1 suggested commitment, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
    )
    #expect(
        many.summary
            == "You can review 3 suggested commitments, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
    )
}

@Test
func planningInvitationPreservesStableActionsAndKeepsVisibleCopyPrivacySafe() {
    let draft = PlanningInvitationPolicy.promptDraft(
        localDay: "2026-07-15-private-day-key",
        itemCount: 2,
        expiresAt: nil
    )

    #expect(draft.actions.map(\.kind) == [
        .reviewPlan,
        .acceptPlan,
        .snoozePlanning,
        .workUnplanned,
        .dismissPlanning
    ])
    #expect(draft.actions.map(\.title) == [
        "Review plan",
        "Accept plan",
        "Snooze 15 min",
        "Work unplanned",
        "Dismiss for now"
    ])
    #expect(!draft.title.contains("2026-07-15-private-day-key"))
    #expect(!draft.summary.contains("2026-07-15-private-day-key"))
}
