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
    #expect(before.sources?.contains(where: { $0.sourceID == "calendar" }) == true)
    #expect(before.sources?.contains(where: { $0.sourceID == "reminders" && $0.detail.contains("Apple Reminders") }) == true)
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
    #expect(try store.priorityRewardMinutes(policy: .firm, day: day) == 15)
    #expect(try store.applyPriorityRewardIfNeeded(taskID: "firm", policy: .firm, day: day) == false)
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

@Test
func dashboardUsesPersistedGamingBudgetAndRewardAcrossAgentRestart() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-persisted-gaming-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let agent = try preparedGamingPolicyAgent(databaseURL: url, day: day, policy: .firm)

    let beforeReward = try agent.snapshot(now: day)
    let afterReward = try agent.apply(.complete, taskID: "priority", now: day)
    let restarted = try TodayDashboardAgent(databaseURL: url)
    let afterRestart = try restarted.snapshot(now: day)

    #expect(beforeReward.gaming.budgetMinutes == 30)
    #expect(beforeReward.gaming.unlockedRemainingMinutes == 30)
    #expect(afterReward.gaming.budgetMinutes == 30)
    #expect(afterReward.gaming.unlockedRemainingMinutes == 60)
    #expect(afterReward.gaming.nextUnlockReason == "Priority-task reward already applied today.")
    #expect(afterRestart.gaming == afterReward.gaming)
}

@Test
func zeroRewardPolicyDoesNotWriteARewardLedgerEntry() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-zero-gaming-reward-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let agent = try preparedGamingPolicyAgent(databaseURL: url, day: day, policy: .flexible)
    _ = try agent.snapshot(now: day)

    let result = try agent.apply(.complete, taskID: "priority", now: day)
    let reward = try TodaySnapshotStore(databaseURL: url)
        .priorityRewardMinutes(policy: .flexible, day: day)

    #expect(reward == nil)
    #expect(result.gaming.unlockedRemainingMinutes == 90)
    #expect(result.gaming.nextUnlockReason == "This policy uses a fixed daily gaming budget.")
}

@Test
func dashboardUsesBalancedGamingDefaultsWhenNoPolicyHasBeenSaved() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-default-gaming-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    let snapshot = try TodayDashboardAgent(databaseURL: url).snapshot()

    #expect(snapshot.gaming.budgetMinutes == 60)
    #expect(snapshot.gaming.unlockedRemainingMinutes == 60)
}

private func preparedGamingPolicyAgent(
    databaseURL: URL,
    day: Date,
    policy: GamingPolicy
) throws -> TodayDashboardAgent {
    _ = try PolicyStore(databaseURL: databaseURL).saveGamingPolicy(policy)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "priority",
            title: "Priority task",
            dueDate: day,
            priority: 9
        )
    ])
    let plans = try AutonomousPlanStore(databaseURL: databaseURL)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(
                    taskID: "priority",
                    title: "Priority task",
                    rank: 1,
                    estimateMinutes: 30,
                    reason: "Due",
                    score: 100
                )
            ],
            mainObjectiveTaskID: "priority",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: day
    )
    return try TodayDashboardAgent(databaseURL: databaseURL)
}
