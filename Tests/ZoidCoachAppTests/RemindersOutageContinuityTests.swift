import Testing
@testable import ZoidCoachApp

@Test
func deniedRemindersExplainsPreservedPlanEstimateAndActiveSession() {
    let state = RemindersContinuityState(
        isOutage: true,
        plannedTaskCount: 2,
        plannedEstimateMinutes: 75,
        hasActiveSession: true
    )

    #expect(state.title == "REMINDERS UNAVAILABLE / LOCAL WORK CONTINUES")
    #expect(state.detail.contains("2 planned tasks"))
    #expect(state.detail.contains("75 estimated minutes"))
    #expect(state.detail.contains("active session keeps tracking locally"))
    #expect(state.detail.contains("repair sync when convenient"))
}

@Test
func outageWithNoPlanStillOffersTruthfulLocalRecovery() {
    let state = RemindersContinuityState(
        isOutage: true,
        plannedTaskCount: 0,
        plannedEstimateMinutes: 0,
        hasActiveSession: false
    )

    #expect(state.detail.contains("0 planned tasks"))
    #expect(state.detail.contains("Create or continue local work now"))
    #expect(!state.detail.contains("active session keeps tracking locally"))
}

@Test
func healthyRemindersDoesNotClaimAnOutage() {
    let state = RemindersContinuityState(
        isOutage: false,
        plannedTaskCount: 1,
        plannedEstimateMinutes: 30,
        hasActiveSession: false
    )

    #expect(state.title == "REMINDERS CONNECTED")
    #expect(state.detail.contains("Local plan and timing data remain stored separately"))
}
