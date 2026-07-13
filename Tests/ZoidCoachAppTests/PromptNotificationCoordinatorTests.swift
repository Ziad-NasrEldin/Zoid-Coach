import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func logicalDecisionUsesStablePrivateRequestIdentityAcrossUpdatedEpisodes() {
    let first = notificationIdentityEpisode(
        id: "episode-1",
        decisionKey: "plan:private-client-title",
        title: "Earlier plan"
    )
    let updated = notificationIdentityEpisode(
        id: "episode-2",
        decisionKey: first.decisionKey,
        title: "Updated plan"
    )
    let separate = notificationIdentityEpisode(
        id: "episode-3",
        decisionKey: "plan:another-private-title",
        title: "Another plan"
    )

    let firstID = PromptNotificationCoordinator.requestIdentifier(
        for: first,
        notificationIdentity: RuntimeIdentity.production.notification
    )
    let updatedID = PromptNotificationCoordinator.requestIdentifier(
        for: updated,
        notificationIdentity: RuntimeIdentity.production.notification
    )
    let separateID = PromptNotificationCoordinator.requestIdentifier(
        for: separate,
        notificationIdentity: RuntimeIdentity.production.notification
    )

    #expect(firstID == updatedID)
    #expect(firstID != separateID)
    #expect(firstID.hasPrefix(RuntimeIdentity.production.notification.promptRequestPrefix + "decision."))
    #expect(!firstID.contains("private-client-title"))
    #expect(!firstID.contains(first.id))
    #expect(firstID.count <= 80)
}

@Test
func emptyDecisionKeyStillReceivesDeterministicPrivateRequestIdentity() {
    let episode = notificationIdentityEpisode(id: "private-episode-id", decisionKey: "", title: "Prompt")
    let first = PromptNotificationCoordinator.requestIdentifier(
        for: episode,
        notificationIdentity: RuntimeIdentity.qa.notification
    )
    let second = PromptNotificationCoordinator.requestIdentifier(
        for: episode,
        notificationIdentity: RuntimeIdentity.qa.notification
    )

    #expect(first == second)
    #expect(first.hasPrefix(RuntimeIdentity.qa.notification.promptRequestPrefix + "decision."))
    #expect(!first.contains(episode.id))
}

@Test
func promptNotificationContractMapsRequiredCategoriesAndActions() {
    #expect(PromptNotificationCategory.forPromptType("PLAN_READY") == .planReady)
    #expect(PromptNotificationCategory.forPromptType("MEETING_CANDIDATE") == .meetingCandidate)
    #expect(PromptNotificationCategory.forPromptType("PLAN_CHANGED") == .planChanged)
    #expect(PromptNotificationCategory.forPromptType("ONBOARDING_TEST") == .onboardingTest)
    #expect(PromptNotificationCategory.forPromptType("GAMING_DRIFT") == .gamingDrift)
    for action in [PromptActionKind.acceptPlan, .reviewPlan, .snoozePlanning, .dismissPlanning, .workUnplanned, .addMeeting, .editMeeting, .ignore, .undoPlanChange] {
        #expect(PromptNotificationCoordinator.actionKind(identifier: PromptNotificationCoordinator.actionIdentifier(action)) == action)
    }
}

@Test
func gamingPromptNotificationAcceptsOnlyBoundedCoachingActions() {
    let identity = RuntimeIdentity.qa.notification
    let allowed: [PromptActionKind] = [
        .returnToActiveTask, .fiveMoreMinutes, .startBreak, .continueIntentionally
    ]
    for action in allowed {
        #expect(PromptNotificationCoordinator.fixtureActionKind(
            identifier: action.rawValue,
            category: PromptNotificationCategory.gamingDrift.rawValue,
            notificationIdentity: identity
        ) == action)
    }
    #expect(PromptNotificationCoordinator.fixtureActionKind(
        identifier: PromptActionKind.acceptPlan.rawValue,
        category: PromptNotificationCategory.gamingDrift.rawValue,
        notificationIdentity: identity
    ) == nil)
}

@Test
func onboardingPromptNotificationAcceptsOnlyItsHarmlessActions() {
    let identity = RuntimeIdentity.qa.notification

    for action in [PromptActionKind.continueIntentionally, .ignore] {
        #expect(PromptNotificationCoordinator.fixtureActionKind(
            identifier: action.rawValue,
            category: PromptNotificationCategory.onboardingTest.rawValue,
            notificationIdentity: identity
        ) == action)
    }
    #expect(PromptNotificationCoordinator.fixtureActionKind(
        identifier: PromptActionKind.acceptPlan.rawValue,
        category: PromptNotificationCategory.onboardingTest.rawValue,
        notificationIdentity: identity
    ) == nil)
}

@Test
func qaPromptNotificationActionsUseOnlyTheQANamespace() {
    let identity = RuntimeIdentity.qa.notification

    for action in [PromptActionKind.acceptPlan, .reviewPlan, .snoozePlanning, .dismissPlanning, .workUnplanned, .addMeeting, .editMeeting, .ignore, .undoPlanChange] {
        let identifier = PromptNotificationCoordinator.actionIdentifier(
            action,
            notificationIdentity: identity
        )
        #expect(identifier.hasPrefix("ZCQA_PROMPT_"))
        #expect(!identifier.contains("ZOID_PROMPT_"))
        #expect(PromptNotificationCoordinator.actionKind(
            identifier: identifier,
            notificationIdentity: identity
        ) == action)
    }

    #expect(identity.actionRequestIdentifier("prompt-1") == "zcqa.action.prompt-1")
    #expect(identity.actionRequestIdentifier("zcqa.action.prompt-1") == "zcqa.action.prompt-1")
    #expect(RuntimeIdentity.production.notification.actionRequestIdentifier("prompt-1") == "prompt-1")
    #expect(UserNotificationActionSource.logicalReceiptIdentifier(for: .init(
        category: "coach",
        title: "Resume",
        body: "Return to focus",
        promptID: "prompt-1",
        deliveryDate: nil
    )) == "prompt-1")
}

private func notificationIdentityEpisode(id: String, decisionKey: String, title: String) -> PromptEpisode {
    PromptEpisode(
        id: id,
        decisionKey: decisionKey,
        type: PromptNotificationCategory.planChanged.rawValue,
        state: .queued,
        title: title,
        summary: "Current summary",
        actions: [.init(kind: .reviewPlan, title: "Review")],
        payload: [:],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        expiresAt: nil,
        presentedAt: nil,
        resolvedAt: nil
    )
}
