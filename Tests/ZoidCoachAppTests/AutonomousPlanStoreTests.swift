import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func autonomousPlanStoreMakesAnAgentDraftAvailableToTheAppForItsTargetDay() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-autonomous-plan-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try AutonomousPlanStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let proposal = DailyPlanProposal(
        items: [
            PlannedTask(
                taskID: "client-review",
                title: "Send client review",
                rank: 1,
                estimateMinutes: 60,
                reason: "Due within 24 hours",
                score: 700
            )
        ],
        mainObjectiveTaskID: "client-review",
        plannedFocusMinutes: 60,
        availableFocusMinutes: 180
    )

    try store.replaceDailyPlan(proposal, for: day)

    #expect(try store.hasPlan(for: day))
}

@Test
func autonomousPlanStoreCanRestoreThePreviousRevisionAfterAReplan() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan-revision-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    let store = try AutonomousPlanStore(databaseURL: url)
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let first = DailyPlanProposal(
        items: [PlannedTask(taskID: "first", title: "First", rank: 1, estimateMinutes: 30, reason: "due today", score: 900)],
        mainObjectiveTaskID: "first",
        plannedFocusMinutes: 30,
        availableFocusMinutes: 120
    )
    let second = DailyPlanProposal(
        items: [PlannedTask(taskID: "second", title: "Second", rank: 1, estimateMinutes: 45, reason: "calendar changed", score: 800)],
        mainObjectiveTaskID: "second",
        plannedFocusMinutes: 45,
        availableFocusMinutes: 120
    )
    try store.replaceDailyPlan(first, for: day)
    try store.replaceDailyPlan(second, for: day)
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["second"])
    #expect(try store.restoreLatestRevision(for: day))
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["first"])
}
