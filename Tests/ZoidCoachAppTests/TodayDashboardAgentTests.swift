import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func agentSnapshotCarriesRequiredDashboardFieldsAndCommandsRefreshIt() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-today-agent-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(id: "priority", title: "Priority task", dueDate: day, priority: 9)])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(DailyPlanProposal(items: [PlannedTask(taskID: "priority", title: "Priority task", rank: 1, estimateMinutes: 30, reason: "Due", score: 100)], mainObjectiveTaskID: "priority", plannedFocusMinutes: 30, availableFocusMinutes: 60), for: day)
    let agent = try TodayDashboardAgent(databaseURL: url)

    let before = try agent.snapshot(now: day)
    let after = try agent.apply(.start, taskID: "priority", now: day)

    #expect(before.timeZoneIdentifier.isEmpty == false)
    #expect(before.mainObjective == "Priority task")
    #expect(before.taskRows.count == 1)
    #expect(before.recommendation.taskID == "priority")
    #expect(after.activeTask?.taskID == "priority")
    #expect(after.taskRows.first?.state == .active)
}

@Test
func gamingRewardLedgerAppliesOnlyOncePerDayAndPolicy() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-gaming-ledger-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try TodaySnapshotStore(databaseURL: url)
    let policy = GamingPolicy()
    let day = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(try store.applyPriorityRewardIfNeeded(taskID: "main", policy: policy, day: day))
    #expect(try store.applyPriorityRewardIfNeeded(taskID: "another", policy: policy, day: day) == false)
    #expect(try store.hasPriorityReward(policy: policy, day: day))
}

@Test
func completingActiveTaskEndsItsIntervalAndRefreshesRecommendation() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-complete-next-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "first", title: "First", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "second", title: "Second", dueDate: nil, priority: 5)
    ])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(DailyPlanProposal(items: [
        PlannedTask(taskID: "first", title: "First", rank: 1, estimateMinutes: 30, reason: "Due", score: 100),
        PlannedTask(taskID: "second", title: "Second", rank: 2, estimateMinutes: 30, reason: "Next", score: 50)
    ], mainObjectiveTaskID: "first", plannedFocusMinutes: 60, availableFocusMinutes: 60), for: day)
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.apply(.start, taskID: "first", now: day)
    let result = try agent.apply(.complete, taskID: "first", now: day.addingTimeInterval(180))

    #expect(result.activeTask == nil)
    #expect(result.taskRows.first(where: { $0.taskID == "first" })?.elapsedMinutes == 3)
    #expect(result.recommendation.taskID == "second")
}
