import Testing
import Foundation
import ZoidCoachCore
@testable import ZoidCoachApp

@Test
func capacityStateExplainsMissingEstimatesBeforeClaimingAPlanIsRealistic() {
    let state = PlanningCapacityState(
        entries: [entry("first", rank: 1, minutes: 30), entry("second", rank: 2, minutes: nil)],
        availableMinutes: 120
    )

    #expect(state.plannedMinutes == 30)
    #expect(state.availableMinutes == 120)
    #expect(state.remainingBufferMinutes == 90)
    #expect(state.overCapacityMinutes == 0)
    #expect(state.readiness == .missingEstimates(count: 1))
    #expect(!state.canApprove)
    #expect(state.suggestedReminderID == nil)
}

@Test
func explicitUnknownEstimateUsesConservativePlaceholderAndAllowsApproval() {
    let state = PlanningCapacityState(
        entries: [
            DailyPlanEntry(
                reminderID: "uncertain",
                rank: 1,
                isMainObjective: true,
                estimateMinutes: nil,
                estimateIsUncertain: true
            )
        ],
        availableMinutes: 60
    )

    #expect(state.plannedMinutes == 45)
    #expect(state.remainingBufferMinutes == 15)
    #expect(state.readiness == .realistic)
    #expect(state.canApprove)
}

@Test
func calendarApprovalKeepsUnknownEstimateVisiblyUncertain() {
    var approval = CalendarPlanApprovalState()
    approval.begin(
        entries: [
            DailyPlanEntry(
                reminderID: "uncertain",
                rank: 1,
                isMainObjective: true,
                estimateMinutes: nil,
                estimateIsUncertain: true
            )
        ],
        titlesByReminderID: ["uncertain": "Investigate production issue"],
        availableMinutes: 60,
        fixedCommitmentMinutes: 0,
        usesCalendarAvailability: false
    )

    #expect(approval.items.count == 1)
    #expect(approval.items[0].estimateMinutes == 45)
    #expect(approval.items[0].estimateIsUncertain == true)
    #expect(approval.plannedMinutes == 45)
}

@Test
func capacityExcludesOptionalAndFutureDeferredTasksWithoutHidingCommittedWork() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let entries = [
        DailyPlanEntry(reminderID: "committed", rank: 1, isMainObjective: true, estimateMinutes: 45),
        DailyPlanEntry(reminderID: "optional", rank: 2, isMainObjective: false, estimateMinutes: 90, isOptional: true),
        DailyPlanEntry(
            reminderID: "deferred",
            rank: 3,
            isMainObjective: false,
            estimateMinutes: nil,
            deferredUntil: now.addingTimeInterval(24 * 60 * 60)
        )
    ]

    let state = PlanningCapacityState(entries: entries, availableMinutes: 60, referenceDate: now)

    #expect(state.plannedMinutes == 45)
    #expect(state.remainingBufferMinutes == 15)
    #expect(state.overCapacityMinutes == 0)
    #expect(state.readiness == .realistic)
    #expect(state.canApprove)
}

@Test
func capacityStateReportsExactOverageAndSuggestsLowestRankedTask() {
    let state = PlanningCapacityState(
        entries: [
            entry("main", rank: 1, minutes: 60),
            entry("secondary", rank: 2, minutes: 45),
            entry("optional", rank: 3, minutes: 30)
        ],
        availableMinutes: 90
    )

    #expect(state.plannedMinutes == 135)
    #expect(state.remainingBufferMinutes == 0)
    #expect(state.overCapacityMinutes == 45)
    #expect(state.readiness == .overloaded(overByMinutes: 45))
    #expect(state.suggestedReminderID == "optional")
    #expect(!state.canApprove)
}

@Test
func capacityStateRecalculatesToRealisticAfterEstimateOrPlanReduction() {
    let overloaded = PlanningCapacityState(
        entries: [entry("main", rank: 1, minutes: 60), entry("later", rank: 2, minutes: 45)],
        availableMinutes: 90
    )
    let shortened = PlanningCapacityState(
        entries: [entry("main", rank: 1, minutes: 45), entry("later", rank: 2, minutes: 45)],
        availableMinutes: 90
    )
    let reduced = PlanningCapacityState(
        entries: [entry("main", rank: 1, minutes: 60)],
        availableMinutes: 90
    )

    #expect(overloaded.readiness == .overloaded(overByMinutes: 15))
    #expect(overloaded.overCapacityMinutes == 15)
    #expect(shortened.readiness == .realistic)
    #expect(shortened.remainingBufferMinutes == 0)
    #expect(shortened.canApprove)
    #expect(reduced.readiness == .realistic)
    #expect(reduced.remainingBufferMinutes == 30)
    #expect(reduced.canApprove)
}

@Test
func zeroCapacityNeverAllowsANonemptyPlanToBeApproved() {
    let state = PlanningCapacityState(
        entries: [entry("task", rank: 1, minutes: 15)],
        availableMinutes: -30
    )

    #expect(state.availableMinutes == 0)
    #expect(state.readiness == .overloaded(overByMinutes: 15))
    #expect(!state.canApprove)
}

@Test
func calendarCapacityMergesOverlapsClipsToWorkHoursAndIgnoresZoidBlocks() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
    let workStart = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
    let workEnd = try #require(calendar.date(byAdding: .hour, value: 17, to: day))
    let commitments = [
        commitment("before", from: workStart.addingTimeInterval(-1_800), minutes: 60),
        commitment("overlap", from: workStart.addingTimeInterval(15 * 60), minutes: 60),
        commitment("owned", from: workStart.addingTimeInterval(2 * 3_600), minutes: 120, owned: true),
        commitment("late", from: workEnd.addingTimeInterval(-30 * 60), minutes: 60)
    ]

    let occupied = PlanningCapacityCalculator().occupiedMinutes(
        workIntervals: [CalendarInterval(start: workStart, end: workEnd)],
        commitments: commitments
    )

    #expect(occupied == 105)
}

@Test
func calendarCapacityUsesOnlyConfiguredVisibleCalendars() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
    let workStart = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
    let workEnd = try #require(calendar.date(byAdding: .hour, value: 17, to: day))
    let commitments = [
        commitment("visible", from: workStart, minutes: 60, calendarIdentifier: "work"),
        commitment("hidden", from: workStart.addingTimeInterval(2 * 3_600), minutes: 120, calendarIdentifier: "personal")
    ]

    let calculator = PlanningCapacityCalculator()
    let selected = calculator.occupiedMinutes(
        workIntervals: [CalendarInterval(start: workStart, end: workEnd)],
        commitments: commitments,
        visibleCalendarIdentifiers: ["work"]
    )
    let all = calculator.occupiedMinutes(
        workIntervals: [CalendarInterval(start: workStart, end: workEnd)],
        commitments: commitments
    )

    #expect(selected == 60)
    #expect(all == 180)
}

private func entry(_ id: String, rank: Int, minutes: Int?) -> DailyPlanEntry {
    DailyPlanEntry(
        reminderID: id,
        rank: rank,
        isMainObjective: rank == 1,
        estimateMinutes: minutes
    )
}

private func commitment(
    _ id: String,
    from start: Date,
    minutes: Int,
    calendarIdentifier: String = "work",
    owned: Bool = false
) -> ZoidCoachApp.CalendarCommitment {
    ZoidCoachApp.CalendarCommitment(
        id: id,
        title: id,
        start: start,
        end: start.addingTimeInterval(TimeInterval(minutes * 60)),
        calendarIdentifier: calendarIdentifier,
        isZoidOwned: owned
    )
}
