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
