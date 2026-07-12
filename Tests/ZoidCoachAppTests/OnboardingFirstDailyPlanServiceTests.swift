import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

private enum FirstPlanPolicyFailure: Error {
    case failed
}

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
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: reminders, now: { now }, planningCapacityOverride: { _ in 240 })

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
func onboardingFirstPlanUsesTheExactConfiguredReminderListIDs() async throws {
    let databaseURL = onboardingPlanDatabaseURL("list-policy")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let opaqueID = "  work-id  "
    let policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        .replacingReminderListPolicy(ReminderListPolicy(
            isConfigured: true,
            decisions: [
                ReminderListDecision(listID: opaqueID, isIncluded: true),
                ReminderListDecision(listID: "personal", isIncluded: false),
            ]
        ))
    _ = try PolicyStore(databaseURL: databaseURL).saveSystemMaintenancePolicy(policy)
    let reminders = FirstPlanRemindersStub(load: .available([
        ReminderTask(id: "included", title: "Included", listID: opaqueID, listName: "Renamed Work", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
        ReminderTask(id: "excluded", title: "Excluded", listID: "personal", listName: "Personal", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
        ReminderTask(id: "unknown", title: "Unknown", listID: "new-list", listName: "New List", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
    ]))
    let service = try OnboardingFirstDailyPlanService(
        databaseURL: databaseURL,
        remindersService: reminders,
        now: { now },
        planningCapacityOverride: { _ in 240 }
    )

    let result = await service.prepare()
    let stored = try ReminderSnapshotStore(databaseURL: databaseURL).loadIncomplete()

    #expect(result.items.map(\.id) == ["included"])
    #expect(stored.filter { $0.sourceKind == .reminders }.map(\.id) == ["included"])
    #expect(stored.first?.listID == opaqueID)
}

@MainActor
@Test
func onboardingFirstPlanFailsClosedWhenListPolicyCannotBeVerified() async throws {
    let databaseURL = onboardingPlanDatabaseURL("list-policy-read-failure")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let service = try OnboardingFirstDailyPlanService(
        databaseURL: databaseURL,
        remindersService: FirstPlanRemindersStub(load: .available([
            ReminderTask(id: "must-not-import", title: "Hidden", listID: "private", listName: "Private", dueDate: now, priority: 1, notes: nil, modificationDate: nil)
        ])),
        now: { now },
        planningCapacityOverride: { _ in 240 },
        reminderListPolicyOverride: { throw FirstPlanPolicyFailure.failed }
    )

    let result = await service.prepare()

    #expect(result.state == .failed)
    #expect(result.items.isEmpty)
    #expect(try ReminderSnapshotStore(databaseURL: databaseURL).loadIncomplete().isEmpty)
}

@MainActor
@Test
func onboardingFirstPlanAllExcludedRemovesImportedRowsButPreservesLocalRows() async throws {
    let databaseURL = onboardingPlanDatabaseURL("all-excluded")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        .replacingReminderListPolicy(ReminderListPolicy(
            isConfigured: true,
            decisions: [ReminderListDecision(listID: "work", isIncluded: false)]
        ))
    _ = try PolicyStore(databaseURL: databaseURL).saveSystemMaintenancePolicy(policy)
    let reminderStore = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminderStore.synchronize([
        ReminderSourceSnapshot(id: "previous-import", title: "Old import", dueDate: nil, priority: 0, listID: "work")
    ])
    let retainedLocal = ReminderSourceSnapshot(
        id: "local-existing",
        title: "Existing local task",
        dueDate: nil,
        priority: 0,
        sourceKind: .local
    )
    _ = try reminderStore.upsertLocal(retainedLocal, observedAt: now)
    let service = try OnboardingFirstDailyPlanService(
        databaseURL: databaseURL,
        remindersService: FirstPlanRemindersStub(load: .available([
            ReminderTask(id: "excluded", title: "Excluded", listID: "work", listName: "Work", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
            ReminderTask(id: "unknown", title: "Unknown", listID: "new-list", listName: "New", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
        ])),
        now: { now },
        planningCapacityOverride: { _ in 240 }
    )

    let result = await service.prepare()
    let stored = try reminderStore.loadIncomplete()

    #expect(result.state == .prepared)
    #expect(result.message.contains("All Reminders lists are excluded"))
    #expect(stored.contains { $0.id == "local-existing" && $0.sourceKind == .local })
    #expect(!stored.contains { $0.sourceKind == .reminders })
    #expect(result.items.allSatisfy { $0.id != "excluded" && $0.id != "unknown" })
}

@MainActor
@Test
func onboardingFirstPlanUsesDurableLocalFallbackWhenRemindersAreUnavailable() async throws {
    let databaseURL = onboardingPlanDatabaseURL("fallback")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let unavailable = FirstPlanRemindersStub(load: .unavailable)
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: unavailable, now: { now }, planningCapacityOverride: { _ in 240 })

    let first = await service.prepare()
    let second = await service.prepare()
    let reminderStore = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminderStore.synchronize([ReminderSourceSnapshot(id: "external", title: "External", dueDate: nil, priority: 0)])
    _ = try reminderStore.synchronize([])
    let restarted = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: unavailable, now: { now }, planningCapacityOverride: { _ in 240 })
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
        ReminderTask(id: "real", title: "Usable task", listID: "work", listName: "Work", dueDate: now, priority: 5, notes: nil, modificationDate: nil)
    ]))
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: reminders, now: { now }, planningCapacityOverride: { _ in 240 })

    let result = await service.prepare()

    #expect(result.state == .prepared)
    #expect(result.items.map(\.id) == ["real"])
    #expect(try planStore.restoreLatestRevision(for: now))
    #expect(try planStore.loadDailyPlan(for: now).map(\.reminderID) == ["missing"])
}

@MainActor
@Test
func onboardingFirstPlanRepairsAPartialOrphanBeforeReturningPrepared() async throws {
    let databaseURL = onboardingPlanDatabaseURL("partial-orphan")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reminderStore = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminderStore.synchronize([
        ReminderSourceSnapshot(id: "visible", title: "Visible task", dueDate: nil, priority: 1)
    ])
    let planStore = try AutonomousPlanStore(databaseURL: databaseURL)
    let partial = DailyPlanProposal(
        items: [
            PlannedTask(taskID: "visible", title: "Visible", rank: 1, estimateMinutes: 30, reason: "test", score: 2),
            PlannedTask(taskID: "missing", title: "Missing", rank: 2, estimateMinutes: 30, reason: "test", score: 1)
        ],
        mainObjectiveTaskID: "visible",
        plannedFocusMinutes: 60,
        availableFocusMinutes: 120
    )
    try planStore.replaceDailyPlan(partial, for: now)
    let reminders = FirstPlanRemindersStub(load: .available([
        ReminderTask(id: "visible", title: "Visible task", listID: "work", listName: "Work", dueDate: nil, priority: 1, notes: nil, modificationDate: nil)
    ]))
    let service = try OnboardingFirstDailyPlanService(databaseURL: databaseURL, remindersService: reminders, now: { now }, planningCapacityOverride: { _ in 240 })

    let result = await service.prepare()

    #expect(result.state == .prepared)
    #expect(result.items.map(\.id) == ["visible"])
    #expect(try planStore.loadDailyPlan(for: now).map(\.reminderID) == ["visible"])
    #expect(try planStore.restoreLatestRevision(for: now))
    #expect(try planStore.loadDailyPlan(for: now).map(\.reminderID) == ["visible", "missing"])
}

@MainActor
@Test
func onboardingFirstPlanUsesOnlyTodayEligibleRemindersAndCapsTheDefaultAtThree() async throws {
    let databaseURL = onboardingPlanDatabaseURL("eligibility")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let future = now.addingTimeInterval(3 * 24 * 60 * 60)
    let tasks = [
        ReminderTask(id: "due-1", title: "Due one", listID: "work", listName: "Work", dueDate: now, priority: 1, notes: nil, modificationDate: nil),
        ReminderTask(id: "due-2", title: "Due two", listID: "work", listName: "Work", dueDate: now, priority: 5, notes: nil, modificationDate: nil),
        ReminderTask(id: "due-3", title: "Due three", listID: "work", listName: "Work", dueDate: now, priority: 5, notes: nil, modificationDate: nil),
        ReminderTask(id: "due-4", title: "Due four", listID: "work", listName: "Work", dueDate: now, priority: 9, notes: nil, modificationDate: nil),
        ReminderTask(id: "future", title: "Future", listID: "work", listName: "Work", dueDate: future, priority: 1, notes: nil, modificationDate: nil),
        ReminderTask(id: "undated", title: "Undated", listID: "work", listName: "Work", dueDate: nil, priority: 1, notes: nil, modificationDate: nil)
    ]
    let service = try OnboardingFirstDailyPlanService(
        databaseURL: databaseURL,
        remindersService: FirstPlanRemindersStub(load: .available(tasks)),
        now: { now },
        planningCapacityOverride: { _ in 240 }
    )

    let result = await service.prepare()

    #expect(result.state == .prepared)
    #expect(result.items.count == 3)
    #expect(!result.items.contains { $0.id == "future" || $0.id == "undated" })
}

@MainActor
@Test
func onboardingFirstPlanFailsHonestlyWhenEligibleWorkExceedsConfiguredCapacity() async throws {
    let databaseURL = onboardingPlanDatabaseURL("capacity")
    defer { removeOnboardingPlanDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reminders = FirstPlanRemindersStub(load: .available([
        ReminderTask(id: "large", title: "Large eligible task", listID: "work", listName: "Work", dueDate: now, priority: 1, notes: nil, modificationDate: nil)
    ]))
    let service = try OnboardingFirstDailyPlanService(
        databaseURL: databaseURL,
        remindersService: reminders,
        now: { now },
        planningCapacityOverride: { _ in 10 }
    )

    let result = await service.prepare()

    #expect(result.state == .unavailable)
    #expect(result.items.isEmpty)
    #expect(result.message.contains("configured planning capacity"))
    #expect(try !AutonomousPlanStore(databaseURL: databaseURL).hasPlan(for: now))
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
