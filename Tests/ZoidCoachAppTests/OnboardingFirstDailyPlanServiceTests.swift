import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func onboardingFirstPlanPersistsRealReminderTasksAndReturnsExactlyWhatTodayCanRender() async throws {
    let databaseURL = onboardingPlanDatabaseURL("real")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reminders = FirstPlanRemindersStub(load: .available([
        ReminderTask(id: "due", title: "Send proposal", listID: "work", listName: "Work", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
        ReminderTask(id: "later", title: "Review notes", listID: "work", listName: "Work", dueDate: nil, priority: 5, notes: nil, modificationDate: nil)
    ]))
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: reminders, now: { now })

    let result = await service.prepare()
    let today = try TodayDashboardAgent(databaseURL: databaseURL).snapshot(now: now)

    #expect(result.state == .prepared)
    #expect(!result.items.isEmpty)
    #expect(result.items == today.taskRows.map {
        OnboardingFirstPlanItem(id: $0.taskID, title: $0.title, estimateMinutes: $0.estimateMinutes, isMainObjective: $0.isMainObjective)
    })
    #expect(result.items.filter(\.isMainObjective).count == 1)
    #expect(result.items.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
}

@MainActor
@Test
func onboardingFirstPlanUsesDurableLocalFallbackWhenRemindersAreUnavailable() async throws {
    let databaseURL = onboardingPlanDatabaseURL("fallback")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let unavailable = FirstPlanRemindersStub(load: .unavailable)
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: unavailable, now: { now })

    let first = await service.prepare()
    let second = await service.prepare()
    let reminderStore = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminderStore.synchronize([ReminderSourceSnapshot(id: "external", title: "External", dueDate: nil, priority: 0)])
    _ = try reminderStore.synchronize([])
    let restarted = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: unavailable, now: { now })
    let afterRestart = await restarted.prepare()

    #expect(first.state == .prepared)
    #expect(first.items.count == 1)
    #expect(first.items.first?.id.hasPrefix("zoid-local:onboarding:") == true)
    #expect(second.items == first.items)
    #expect(afterRestart.items == first.items)
    #expect(try reminderStore.loadIncomplete().contains { $0.id == first.items[0].id && $0.sourceKind == .local })
    #expect(try !AutonomousPlanStore(databaseURL: databaseURL).restoreLatestRevision(for: now))

    let requests = try PlanScheduleRequestStore(databaseURL: databaseURL)
    #expect(try requests.claimNext() != nil)
    #expect(try requests.claimNext() == nil)
}

@MainActor
@Test
func onboardingFirstPlanRepairsAnOrphanInsteadOfClaimingItIsPrepared() async throws {
    let databaseURL = onboardingPlanDatabaseURL("orphan")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let planStore = try AutonomousPlanStore(databaseURL: databaseURL)
    try planStore.replaceDailyPlan(onboardingTestProposal(id: "missing"), for: now)
    let reminders = FirstPlanRemindersStub(load: .available([
        ReminderTask(id: "real", title: "Usable task", listID: "work", listName: "Work", dueDate: nil, priority: 5, notes: nil, modificationDate: nil)
    ]))
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: reminders, now: { now })

    let result = await service.prepare()

    #expect(result.state == .prepared)
    #expect(result.items.map(\.id) == ["real"])
    #expect(try planStore.restoreLatestRevision(for: now))
    #expect(try planStore.loadDailyPlan(for: now).map(\.reminderID) == ["missing"])
}

@MainActor
private final class FirstPlanRemindersStub: RemindersServicing {
    let isProductionAdapter = false
    var load: ReminderTaskLoad

    init(load: ReminderTaskLoad) {
        self.load = load
    }

    func inspect() async -> SourceHealth {
        SourceHealth(
            id: .reminders,
            title: "Reminders",
            eyebrow: "Tasks",
            state: .healthy,
            detail: "test",
            evidence: "test",
            actionTitle: "Inspect"
        )
    }

    func requestAccessAndInspect() async -> SourceHealth {
        await inspect()
    }

    func fetchIncompleteTasks() async -> ReminderTaskLoad {
        load
    }
}

private func onboardingPlanDatabaseURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-first-plan-\(label)-\(UUID().uuidString).sqlite")
}

private func removeOnboardingPlanDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private func onboardingTestProposal(id: String) -> DailyPlanProposal {
    DailyPlanProposal(
        items: [PlannedTask(taskID: id, title: id, rank: 1, estimateMinutes: 30, reason: "test", score: 1)],
        mainObjectiveTaskID: id,
        plannedFocusMinutes: 30,
        availableFocusMinutes: 60
    )
}
