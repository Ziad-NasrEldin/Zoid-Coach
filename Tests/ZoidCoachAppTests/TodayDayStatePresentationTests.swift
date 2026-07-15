import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func dayStatePresentationCoversEveryPlanningMode() {
    let cases: [(PlanningDayMode, TodayDayStatePresentation.Kind, String)] = [
        (.invitation, .invitation, "PLAN NEEDED"),
        (.snoozed, .snoozed, "PLANNING SNOOZED"),
        (.dismissed, .dismissed, "PLANNING DISMISSED"),
        (.planning, .planned, "PLANNED DAY"),
        (.unplanned, .unplanned, "UNPLANNED DAY"),
    ]

    for (mode, expectedKind, expectedTitle) in cases {
        let presentation = TodayDayStatePresentation.resolve(
            snapshotIsAvailable: true,
            planningMode: mode,
            hasActiveTask: false,
            hasPlannedTasks: true
        )
        #expect(presentation.kind == expectedKind)
        #expect(presentation.title == expectedTitle)
        #expect(!presentation.detail.isEmpty)
    }
}

@Test
func activeTaskIsTheDayStateRegardlessOfPlanningLifecycle() {
    for mode in PlanningDayMode.allCasesForDayStateTests {
        let presentation = TodayDayStatePresentation.resolve(
            snapshotIsAvailable: true,
            planningMode: mode,
            hasActiveTask: true,
            hasPlannedTasks: true
        )
        #expect(presentation.kind == .active)
        #expect(presentation.title == "ACTIVE WORK")
    }
}

@Test
func pausedTaskIsExplicitWhenNoTaskIsActive() {
    let presentation = TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: .planning,
        hasActiveTask: false,
        hasPlannedTasks: true,
        hasPausedTask: true
    )

    #expect(presentation.kind == .paused)
    #expect(presentation.title == "WORK PAUSED")
    #expect(presentation.detail == "A task is paused and ready to resume.")
    #expect(presentation.accessibilityValue == "paused")
}

@Test
func allCompletedTasksProduceAnExplicitCompletedDayState() {
    let presentation = TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: .planning,
        hasActiveTask: false,
        hasPlannedTasks: true,
        allPlannedTasksCompleted: true
    )

    #expect(presentation.kind == .completed)
    #expect(presentation.title == "WORK COMPLETED")
    #expect(presentation.detail == "Every visible task for today is completed.")
    #expect(presentation.accessibilityValue == "completed")
}

@Test
func activePausedAndCompletedStatesUseTruthfulPrecedence() {
    let active = TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: .planning,
        hasActiveTask: true,
        hasPlannedTasks: true,
        hasPausedTask: true,
        allPlannedTasksCompleted: true
    )
    let paused = TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: .planning,
        hasActiveTask: false,
        hasPlannedTasks: true,
        hasPausedTask: true,
        allPlannedTasksCompleted: true
    )
    let mixedPlan = TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: .planning,
        hasActiveTask: false,
        hasPlannedTasks: true,
        hasPausedTask: false,
        allPlannedTasksCompleted: false
    )

    #expect(active.kind == .active)
    #expect(paused.kind == .paused)
    #expect(mixedPlan.kind == .planned)
}

@Test
func unavailableAndLegacySnapshotsRemainHonest() {
    #expect(TodayDayStatePresentation.resolve(
        snapshotIsAvailable: false,
        planningMode: nil,
        hasActiveTask: false,
        hasPlannedTasks: false
    ).kind == .preparing)

    #expect(TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: nil,
        hasActiveTask: false,
        hasPlannedTasks: true
    ).kind == .planned)

    #expect(TodayDayStatePresentation.resolve(
        snapshotIsAvailable: true,
        planningMode: nil,
        hasActiveTask: false,
        hasPlannedTasks: false
    ).kind == .open)
}

private extension PlanningDayMode {
    static let allCasesForDayStateTests: [PlanningDayMode] = [
        .invitation, .snoozed, .dismissed, .planning, .unplanned,
    ]
}
