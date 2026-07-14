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
