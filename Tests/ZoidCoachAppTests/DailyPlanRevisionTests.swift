import Foundation
import Testing
import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func dailyPlanRevisionPersistsOrderOptionalAndDeferralAcrossRestart() throws {
    let url = revisionDatabaseURL("persistence")
    defer { removeRevisionDatabase(url) }
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let deferredUntil = day.addingTimeInterval(24 * 60 * 60)

    let writer = try AgentOwnedStateStore(databaseURL: url)
    try writer.replaceDailyPlan([
        AgentPlanItem(
            reminderID: "second",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: 30,
            selectionReason: "Moved ahead deliberately.",
            selectionScore: 20
        ),
        AgentPlanItem(
            reminderID: "first",
            rank: 2,
            isMainObjective: false,
            estimateMinutes: 45,
            selectionReason: "Useful if capacity remains.",
            selectionScore: 10,
            isOptional: true,
            deferredUntil: deferredUntil
        )
    ], day: day, now: day)

    let restarted = try AutonomousPlanStore(databaseURL: url).loadDailyPlan(for: day)
    #expect(restarted.map(\.reminderID) == ["second", "first"])
    #expect(restarted.map(\.rank) == [1, 2])
    #expect(restarted[1].isOptional == true)
    #expect(restarted[1].deferredUntil == deferredUntil)
}

@Test
func blockedReasonAndExecutionStateCommitTogetherAndRecoverAfterRestart() throws {
    let url = revisionDatabaseURL("blocked")
    defer { removeRevisionDatabase(url) }
    let now = Date(timeIntervalSince1970: 1_800_100_000)

    try AgentOwnedStateStore(databaseURL: url).replaceDailyPlan([
        AgentPlanItem(
            reminderID: "blocked-task",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: 30,
            selectionReason: nil,
            selectionScore: nil
        )
    ], day: now, now: now)

    let execution = try TaskExecutionStore(databaseURL: url)
    try execution.apply(
        .block,
        taskID: "blocked-task",
        blockedReason: "Waiting for the client to approve the final copy.",
        at: now
    )

    let restartedExecution = try TaskExecutionStore(databaseURL: url)
    let state = try restartedExecution.snapshot(for: ["blocked-task"], now: now)["blocked-task"]
    let plan = try AutonomousPlanStore(databaseURL: url).loadDailyPlan(for: now)
    #expect(state?.state == .blocked)
    #expect(plan.first?.blockedReason == "Waiting for the client to approve the final copy.")

    try restartedExecution.apply(.reschedule, taskID: "blocked-task", at: now.addingTimeInterval(60))
    let revised = try AutonomousPlanStore(databaseURL: url).loadDailyPlan(for: now)
    #expect(revised.first?.blockedReason == nil)
}

@Test
func invalidBlockedReasonLeavesBothPlanAndExecutionUnchanged() throws {
    let url = revisionDatabaseURL("invalid-blocked")
    defer { removeRevisionDatabase(url) }
    let now = Date(timeIntervalSince1970: 1_800_200_000)

    try AgentOwnedStateStore(databaseURL: url).replaceDailyPlan([
        AgentPlanItem(
            reminderID: "task",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: 30,
            selectionReason: nil,
            selectionScore: nil
        )
    ], day: now, now: now)
    let store = try TaskExecutionStore(databaseURL: url)

    #expect(throws: TaskExecutionStoreError.invalidBlockedReason) {
        try store.apply(.block, taskID: "task", blockedReason: "x", at: now)
    }
    #expect(try store.snapshot(for: ["task"], now: now)["task"]?.state == .ready)
    #expect(try AutonomousPlanStore(databaseURL: url).loadDailyPlan(for: now).first?.blockedReason == nil)
}

private func revisionDatabaseURL(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-daily-plan-revision-\(suffix)-\(UUID().uuidString).sqlite")
}

private func removeRevisionDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
    }
}
