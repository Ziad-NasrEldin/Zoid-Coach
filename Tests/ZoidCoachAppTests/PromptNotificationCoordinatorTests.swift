import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func promptNotificationContractMapsRequiredCategoriesAndActions() {
    #expect(PromptNotificationCategory.forPromptType("PLAN_READY") == .planReady)
    #expect(PromptNotificationCategory.forPromptType("MEETING_CANDIDATE") == .meetingCandidate)
    #expect(PromptNotificationCategory.forPromptType("PLAN_CHANGED") == .planChanged)
    for action in [PromptActionKind.acceptPlan, .reviewPlan, .addMeeting, .editMeeting, .ignore, .undoPlanChange] {
        #expect(PromptNotificationCoordinator.actionKind(identifier: PromptNotificationCoordinator.actionIdentifier(action)) == action)
    }
}

@Test
func qaPromptNotificationActionsUseOnlyTheQANamespace() {
    let identity = RuntimeIdentity.qa.notification

    for action in [PromptActionKind.acceptPlan, .reviewPlan, .addMeeting, .editMeeting, .ignore, .undoPlanChange] {
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
