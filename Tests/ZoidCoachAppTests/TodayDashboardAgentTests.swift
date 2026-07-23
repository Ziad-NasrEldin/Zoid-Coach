import Foundation
import SQLite3
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
    #expect(before.activeTaskContext == nil)
    #expect(after.activeTask?.taskID == "priority")
    #expect(after.activeTaskContext?.state == .uncertain)
    #expect(after.activeTaskContext?.explanation.contains("will not guess") == true)
    #expect(after.taskRows.first?.state == .active)
}

@Test
func agentSnapshotShowsOnlyObservedAlignmentFromTheCurrentActiveSession() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-active-time-comparison-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let activeSince = Date(timeIntervalSince1970: 1_750_000_000)
    let now = activeSince.addingTimeInterval(180)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "focus", title: "Write proposal", dueDate: now, priority: 9)
    ])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "focus", title: "Write proposal", rank: 1, estimateMinutes: 30, reason: "Main", score: 100)
            ],
            mainObjectiveTaskID: "focus",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: activeSince
    )
    let agent = try TodayDashboardAgent(databaseURL: url)
    _ = try agent.apply(.start, taskID: "focus", now: activeSince)

    var database: OpaquePointer?
    try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let records = [
        (activeSince.addingTimeInterval(-60), "Xcode", "work"),
        (activeSince, "Steam", "gaming"),
        (activeSince.addingTimeInterval(60), "Xcode", "work"),
        (activeSince.addingTimeInterval(120), "Terminal", "work")
    ]
    for (observedAt, application, classification) in records {
        let sql = """
        INSERT INTO behavior_records(
            source_day, epoch, time_label, app_name, window_title, url,
            has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
        ) VALUES (
            '2025-06-15', \(Int(observedAt.timeIntervalSince1970)), '00-00-00',
            '\(application)', '', '', 0, NULL, '2025-06-15T00:00:00Z', '\(classification)', 1
        );
        """
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    let snapshot = try agent.snapshot(now: now)
    let comparison = try #require(snapshot.taskRows.first?.activeTimeComparison)

    #expect(comparison.elapsedMinutes == 3)
    #expect(comparison.observedAlignedMinutes == 2)
    #expect(comparison.observedSessionMinutes == 3)
    #expect(comparison.evidenceExplanation.contains("signal, not proof"))
}

@Test
func blockingMainObjectiveDurablyPromotesNextUsableTask() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-blocked-replan-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "main", title: "Submit proposal", dueDate: now, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Prepare supporting notes", dueDate: now, priority: 5),
        ReminderSourceSnapshot(id: "later", title: "Archive research", dueDate: nil, priority: 1)
    ])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "main", title: "Submit proposal", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
                PlannedTask(taskID: "next", title: "Prepare supporting notes", rank: 2, estimateMinutes: 25, reason: "Next", score: 80),
                PlannedTask(taskID: "later", title: "Archive research", rank: 3, estimateMinutes: 15, reason: "Later", score: 40)
            ],
            mainObjectiveTaskID: "main",
            plannedFocusMinutes: 70,
            availableFocusMinutes: 90
        ),
        for: now
    )
    let agent = try TodayDashboardAgent(databaseURL: url)
    _ = try agent.apply(.start, taskID: "main", now: now)
    let replanned = try agent.apply(
        .block,
        taskID: "main",
        blockedReason: "Waiting for the client to approve the source material.",
        now: now.addingTimeInterval(60)
    )

    #expect(replanned.mainObjective == "Prepare supporting notes")
    #expect(replanned.taskRows.first(where: { $0.taskID == "main" })?.state == .blocked)
    #expect(replanned.taskRows.first(where: { $0.taskID == "main" })?.blockedReason == "Waiting for the client to approve the source material.")
    #expect(replanned.taskRows.first(where: { $0.taskID == "next" })?.isMainObjective == true)
    #expect(replanned.recommendation.taskID == "next")

    let restarted = try TodayDashboardAgent(databaseURL: url).snapshot(now: now.addingTimeInterval(120))
    #expect(restarted.mainObjective == "Prepare supporting notes")
    #expect(restarted.taskRows.first(where: { $0.taskID == "main" })?.blockedReason == "Waiting for the client to approve the source material.")
    #expect(try plans.restoreLatestRevision(for: now))
    #expect(try plans.loadDailyPlan(for: now).first(where: { $0.reminderID == "main" })?.isMainObjective == true)
}

@Test
func blockingMainObjectiveWithoutUsableReplacementKeepsPlanHonest() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-blocked-no-replacement-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(id: "only", title: "Only task", dueDate: now, priority: 9)])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "only", title: "Only task", rank: 1, estimateMinutes: 30, reason: "Only", score: 100)],
            mainObjectiveTaskID: "only",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: now
    )
    let agent = try TodayDashboardAgent(databaseURL: url)
    _ = try agent.apply(.start, taskID: "only", now: now)
    let blocked = try agent.apply(
        .block,
        taskID: "only",
        blockedReason: "Waiting for an external dependency.",
        now: now.addingTimeInterval(30)
    )

    #expect(blocked.mainObjective == "Only task")
    #expect(blocked.taskRows.first?.state == .blocked)
    #expect(try plans.loadDailyPlan(for: now).filter(\.isMainObjective).map(\.reminderID) == ["only"])
}

@Test
func unplannedTaskStartIsVisiblePersistsAndNeverInventsAPlanViolation() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-unplanned-start-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let now = Date()
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "unplanned", title: "Write the outline", dueDate: now, priority: 9),
        ReminderSourceSnapshot(id: "later", title: "Review notes", dueDate: nil, priority: 1)
    ])
    let agent = try TodayDashboardAgent(databaseURL: url)

    let before = try agent.skipPlanning(now: now)
    #expect(before.taskRows.isEmpty)
    #expect(before.planningStatus == PlanningDayStatus(mode: .unplanned, driftInterventionsAllowed: false))
    #expect(before.unplannedReminders?.map(\.reminderID).sorted() == ["later", "unplanned"])

    let started = try agent.startUnplannedTask("unplanned", now: now.addingTimeInterval(1))
    #expect(started.mainObjective == nil)
    #expect(started.activeTask?.taskID == "unplanned")
    #expect(started.taskRows.first(where: { $0.taskID == "unplanned" })?.state == .active)
    #expect(started.planningStatus == PlanningDayStatus(mode: .unplanned, driftInterventionsAllowed: true))

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: now.addingTimeInterval(61))
    #expect(restored.activeTask?.taskID == "unplanned")
    #expect(restored.taskRows.first?.title == "Write the outline")
    #expect(restored.planningStatus?.mode == .unplanned)
    #expect(restored.mainObjective == nil)
}

@Test
func todayQueueIncludesOverdueTodayAndUndatedButExcludesUnselectedFutureTasks() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-today-eligibility-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 12))!
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "overdue", title: "Overdue", dueDate: calendar.date(byAdding: .day, value: -1, to: now), priority: 1),
        ReminderSourceSnapshot(id: "today", title: "Today", dueDate: calendar.date(bySettingHour: 23, minute: 30, second: 0, of: now), priority: 1),
        ReminderSourceSnapshot(id: "undated", title: "Undated", dueDate: nil, priority: 1),
        ReminderSourceSnapshot(id: "future", title: "Future", dueDate: calendar.date(byAdding: .day, value: 1, to: now), priority: 1),
        ReminderSourceSnapshot(id: "planned-future", title: "Selected future", dueDate: calendar.date(byAdding: .day, value: 2, to: now), priority: 1),
    ])
    let policies = try PolicyStore(databaseURL: url)
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    _ = try policies.saveSystemMaintenancePolicy(defaults)
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "planned-future", title: "Selected future", rank: 1, estimateMinutes: 30, reason: "Selected", score: 1)],
            mainObjectiveTaskID: "planned-future",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: now
    )

    let snapshot = try TodayDashboardAgent(databaseURL: url).snapshot(now: now)
    #expect(Set(snapshot.unplannedReminders?.map(\.reminderID) ?? []) == Set(["overdue", "today", "undated"]))
    #expect(snapshot.taskRows.contains(where: { $0.taskID == "planned-future" }))
    #expect(snapshot.unplannedReminders?.contains(where: { $0.reminderID == "future" }) == false)
}

@Test
func todayQueueUsesReminderListPolicyForPlannedAndUnplannedReminders() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-list-policy-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "included",
            title: "Included due today",
            dueDate: now,
            priority: 1,
            listID: "work",
            listName: "Work",
            sourceKind: .reminders
        ),
        ReminderSourceSnapshot(
            id: "excluded",
            title: "Excluded due today",
            dueDate: now,
            priority: 1,
            listID: "personal",
            listName: "Personal",
            sourceKind: .reminders
        ),
        ReminderSourceSnapshot(
            id: "undated-local",
            title: "Local fallback",
            dueDate: nil,
            priority: 1,
            listID: "zoid-local",
            listName: "Zoid 666",
            sourceKind: .local
        )
    ])
    let policies = try PolicyStore(databaseURL: url)
    let configuredPolicy = UserPolicy.defaults(timeZoneIdentifier: "UTC").replacingReminderListPolicy(
        .init(
            isConfigured: true,
            decisions: [
                ReminderListDecision(listID: "work", isIncluded: true),
                ReminderListDecision(listID: "personal", isIncluded: false)
            ]
        )
    )
    _ = try policies.saveSystemMaintenancePolicy(configuredPolicy)
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "included", title: "Included due today", rank: 1, estimateMinutes: 30, reason: "Due", score: 1),
                PlannedTask(taskID: "excluded", title: "Excluded due today", rank: 2, estimateMinutes: 20, reason: "Due", score: 1),
                PlannedTask(taskID: "undated-local", title: "Local fallback", rank: 3, estimateMinutes: 20, reason: "Local", score: 1)
            ],
            mainObjectiveTaskID: "included",
            plannedFocusMinutes: 70,
            availableFocusMinutes: 90
        ),
        for: now
    )

    let snapshot = try TodayDashboardAgent(databaseURL: url).snapshot(now: now)
    #expect(snapshot.taskRows.map(\.taskID).sorted() == ["included", "undated-local"])
    #expect(snapshot.taskRows.contains(where: { $0.taskID == "excluded" }) == false)
}

@Test
func todayQueueDeduplicatesDuplicatePlanIDsInTaskRows() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-dupe-plan-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "dupe", title: "Duplicate reminder", dueDate: now, priority: 1),
        ReminderSourceSnapshot(id: "single", title: "Single reminder", dueDate: now, priority: 1)
    ])
    let plan = try AutonomousPlanStore(databaseURL: url)
    try plan.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "dupe", title: "Duplicate reminder", rank: 1, estimateMinutes: 30, reason: "Due", score: 100),
                PlannedTask(taskID: "dupe", title: "Duplicate reminder", rank: 2, estimateMinutes: 30, reason: "Due", score: 99),
                PlannedTask(taskID: "single", title: "Single reminder", rank: 3, estimateMinutes: 30, reason: "Due", score: 1),
            ],
            mainObjectiveTaskID: "dupe",
            plannedFocusMinutes: 90,
            availableFocusMinutes: 90
        ),
        for: now
    )
    let policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    _ = try PolicyStore(databaseURL: url).saveSystemMaintenancePolicy(policy)

    let snapshot = try TodayDashboardAgent(databaseURL: url).snapshot(now: now)
    #expect(snapshot.taskRows.filter { $0.taskID == "dupe" }.count == 1)
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
    #expect(result.taskRows.contains { $0.taskID == "first" } == false)
    #expect(result.recommendation.taskID == "second")
}

@Test
func completingLocalTaskStaysLocalRecordsHistoryAndSurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-local-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let taskID = "local:user:completion"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    _ = try reminders.createLocal(ReminderSourceSnapshot(
        id: taskID,
        title: "Finish the local draft",
        dueDate: nil,
        priority: 0,
        listID: "local:user",
        listName: "Local Tasks",
        modificationDate: day,
        sourceKind: .local
    ))
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Finish the local draft", rank: 1, estimateMinutes: 25, reason: "Local", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.apply(.start, taskID: taskID, now: day)
    let completed = try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(300))

    #expect(completed.activeTask == nil)
    #expect(completed.taskRows.contains { $0.taskID == taskID } == false)
    #expect(try reminders.loadIncomplete().contains { $0.id == taskID } == false)
    #expect(try TaskHistoryStore(databaseURL: url).summary(for: day).completedCount == 1)
    #expect(try ActionOutboxStore(databaseURL: url).recentCommands().contains { $0.entityID == taskID } == false)

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: day.addingTimeInterval(600))
    #expect(restored.taskRows.contains { $0.taskID == taskID } == false)
    #expect(restored.unplannedReminders?.contains { $0.reminderID == taskID } == false)
}

@Test
func completingReminderTaskLeavesTodayImmediatelyWhileSourceWriteIsPending() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-reminder-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let completedAt = day.addingTimeInterval(300)
    let taskID = "reminder:pending-completion"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(
        id: taskID,
        title: "Send the finished brief",
        dueDate: day,
        priority: 9,
        modificationDate: day,
        sourceKind: .reminders
    )])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Send the finished brief", rank: 1, estimateMinutes: 25, reason: "Due", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.apply(.start, taskID: taskID, now: day)
    let completed = try agent.apply(.complete, taskID: taskID, now: completedAt)

    #expect(completed.activeTask == nil)
    #expect(completed.taskRows.contains { $0.taskID == taskID } == false)
    #expect(completed.unplannedReminders?.contains { $0.reminderID == taskID } == false)
    #expect(try reminders.loadIncomplete().contains { $0.id == taskID })
    #expect(try ActionOutboxStore(databaseURL: url).recentCommands().contains { $0.entityID == taskID })
    let history = try TaskHistoryStore(databaseURL: url).completedEntries(for: completedAt)
    #expect(history.map(\.title) == ["Send the finished brief"])
    #expect(history.map(\.sourceKind) == [.reminders])
}

@Test
func failedReminderCompletionCanBeRetriedExactlyOnceWithoutLosingHistory() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-retry-reminder-completion-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let taskID = "reminder:retry-completion"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(
        id: taskID,
        title: "Send the final brief",
        dueDate: day,
        priority: 9,
        sourceKind: .reminders
    )])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Send the final brief", rank: 1, estimateMinutes: 25, reason: "Due", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.apply(.start, taskID: taskID, now: day)
    _ = try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(120))
    let pending = try agent.reminderCompletionSyncState(taskID: taskID)
    #expect(pending.phase == .pending)
    #expect(pending.taskTitle == "Send the final brief")

    let outbox = try ActionOutboxStore(databaseURL: url)
    let claimed = try #require(try outbox.claimNextReady())
    try outbox.markFailed(claimed, retryable: false, redactedError: "Reminders access denied")
    #expect(try agent.reminderCompletionSyncState(taskID: taskID).phase == .failed)

    let retried = try agent.retryReminderCompletion(taskID: taskID)
    #expect(retried.phase == .pending)
    let secondAttempt = try #require(try outbox.claimNextReady())
    #expect(secondAttempt.id == claimed.id)
    #expect(secondAttempt.attemptCount == 2)
    #expect(try TaskHistoryStore(databaseURL: url).completedEntries(for: day).map(\.taskID) == [taskID])
    #expect(throws: TodayDashboardAgentError.self) {
        try agent.retryReminderCompletion(taskID: taskID)
    }
}

@Test
func temporaryDatabaseLockRetriesTheCompleteUserMutationExactlyOnce() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-lock-retry-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let taskID = "reminder:locked-completion"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(
        id: taskID,
        title: "Complete through a temporary lock",
        dueDate: day,
        priority: 9,
        sourceKind: .reminders
    )])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Complete through a temporary lock", rank: 1, estimateMinutes: 25, reason: "Due", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)
    _ = try agent.apply(.start, taskID: taskID, now: day)

    var rawBlocker: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &rawBlocker, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
    let blocker = try #require(rawBlocker)
    defer { sqlite3_close(blocker) }
    #expect(sqlite3_exec(blocker, "BEGIN EXCLUSIVE TRANSACTION;", nil, nil, nil) == SQLITE_OK)

    let completion = Task.detached {
        try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(120))
    }
    try await Task.sleep(for: .milliseconds(80))
    #expect(sqlite3_exec(blocker, "COMMIT;", nil, nil, nil) == SQLITE_OK)
    let completed = try await completion.value

    #expect(completed.taskRows.contains { $0.taskID == taskID } == false)
    #expect(try TaskHistoryStore(databaseURL: url).completedEntries(for: day).map(\.taskID) == [taskID])
    let completions = try ActionOutboxStore(databaseURL: url).recentCommands().filter {
        $0.type == .completeReminder && $0.entityID == taskID
    }
    #expect(completions.count == 1)
    #expect(try TaskExecutionStore(databaseURL: url).snapshot(for: [taskID], now: day.addingTimeInterval(180))[taskID]?.state == .completed)
}

@Test
func persistentDatabaseLockFailsWithinTheMutationRetryBoundWithoutPartialCompletion() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-lock-bound-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let taskID = "reminder:persistent-lock"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(
        id: taskID,
        title: "Keep the confirmed state",
        dueDate: day,
        priority: 9,
        sourceKind: .reminders
    )])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Keep the confirmed state", rank: 1, estimateMinutes: 25, reason: "Due", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url, mutationLockRetryDelays: [0.01, 0.02])
    _ = try agent.apply(.start, taskID: taskID, now: day)

    var rawBlocker: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &rawBlocker, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
    let blocker = try #require(rawBlocker)
    defer {
        _ = sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil)
        sqlite3_close(blocker)
    }
    #expect(sqlite3_exec(blocker, "BEGIN EXCLUSIVE TRANSACTION;", nil, nil, nil) == SQLITE_OK)

    let startedAt = Date()
    #expect(throws: (any Error).self) {
        try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(120))
    }
    #expect(Date().timeIntervalSince(startedAt) < 0.5)
    #expect(sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil) == SQLITE_OK)
    #expect(try TaskHistoryStore(databaseURL: url).completedEntries(for: day).isEmpty)
    #expect(try ActionOutboxStore(databaseURL: url).recentCommands().allSatisfy { $0.entityID != taskID })
}

@Test
func nonLockMutationFailureDoesNotEnterTheDatabaseRetrySchedule() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-non-lock-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let agent = try TodayDashboardAgent(databaseURL: url, mutationLockRetryDelays: [1, 1])

    let startedAt = Date()
    #expect(throws: TaskExecutionStoreError.self) {
        try agent.apply(.block, taskID: "task", blockedReason: "x", now: day)
    }
    #expect(Date().timeIntervalSince(startedAt) < 0.5)
}

@Test
func downstreamFailureDoesNotDuplicateRawHistoryWhenTheUserRetries() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-complete-downstream-failure-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let taskID = "reminder:downstream-failure"
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(
        id: taskID,
        title: "Complete once after a downstream failure",
        dueDate: day,
        priority: 9,
        sourceKind: .reminders
    )])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: taskID, title: "Complete once after a downstream failure", rank: 1, estimateMinutes: 25, reason: "Due", score: 100)],
            mainObjectiveTaskID: taskID,
            plannedFocusMinutes: 25,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)
    _ = try agent.apply(.start, taskID: taskID, now: day)

    var rawDatabase: OpaquePointer?
    try #require(sqlite3_open_v2(url.path, &rawDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
    let database = try #require(rawDatabase)
    defer { sqlite3_close(database) }
    try #require(sqlite3_exec(
        database,
        "CREATE TRIGGER fail_learning_sample BEFORE INSERT ON learning_samples BEGIN SELECT RAISE(ABORT, 'forced downstream failure'); END;",
        nil,
        nil,
        nil
    ) == SQLITE_OK)

    #expect(throws: (any Error).self) {
        try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(120))
    }
    try #require(sqlite3_exec(database, "DROP TRIGGER fail_learning_sample;", nil, nil, nil) == SQLITE_OK)
    _ = try agent.apply(.complete, taskID: taskID, now: day.addingTimeInterval(120))

    var rawStatement: OpaquePointer?
    try #require(sqlite3_prepare_v2(
        database,
        "SELECT COUNT(*) FROM task_history WHERE task_id = ? AND state = 'completed';",
        -1,
        &rawStatement,
        nil
    ) == SQLITE_OK)
    let statement = try #require(rawStatement)
    defer { sqlite3_finalize(statement) }
    try taskID.withCString {
        try #require(sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK)
    }
    try #require(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 1)
    #expect(try ActionOutboxStore(databaseURL: url).recentCommands().filter {
        $0.type == .completeReminder && $0.entityID == taskID
    }.count == 1)
}

@Test
func agentPauseSwitchResumeAndCompletePausedJourneySurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-task-lifecycle-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "first", title: "Write the brief", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "second", title: "Review the draft", dueDate: day, priority: 5)
    ])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(DailyPlanProposal(items: [
        PlannedTask(taskID: "first", title: "Write the brief", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
        PlannedTask(taskID: "second", title: "Review the draft", rank: 2, estimateMinutes: 20, reason: "Next", score: 50)
    ], mainObjectiveTaskID: "first", plannedFocusMinutes: 50, availableFocusMinutes: 60), for: day)
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.apply(.start, taskID: "first", now: day)
    let pausedForBreak = try agent.apply(.pauseForBreak, taskID: "first", now: day.addingTimeInterval(300))
    #expect(pausedForBreak.taskRows.first(where: { $0.taskID == "first" })?.latestPauseReason == .break)
    #expect(pausedForBreak.taskRows.first(where: { $0.taskID == "first" })?.elapsedMinutes == 5)

    _ = try agent.apply(.resume, taskID: "first", now: day.addingTimeInterval(600))
    let switched = try agent.apply(.start, taskID: "second", now: day.addingTimeInterval(720))
    let firstAfterSwitch = switched.taskRows.first(where: { $0.taskID == "first" })
    #expect(firstAfterSwitch?.state == .paused)
    #expect(firstAfterSwitch?.latestPauseReason == .switchingTasks)
    #expect(firstAfterSwitch?.elapsedMinutes == 7)
    #expect(switched.activeTask?.taskID == "second")

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: day.addingTimeInterval(840))
    #expect(restored.activeTask?.taskID == "second")
    #expect(restored.taskRows.first(where: { $0.taskID == "first" })?.latestPauseReason == .switchingTasks)

    _ = try restarted.apply(.pauseDoneForNow, taskID: "second", now: day.addingTimeInterval(900))
    let completedPaused = try restarted.apply(.complete, taskID: "second", now: day.addingTimeInterval(960))
    #expect(completedPaused.activeTask == nil)
    #expect(completedPaused.taskRows.contains { $0.taskID == "second" } == false)
    let completedHistory = try TaskHistoryStore(databaseURL: url)
        .completedEntries(for: day.addingTimeInterval(960))
    #expect(completedHistory.first(where: { $0.taskID == "second" })?.lastPauseReason == .doneForNow)
}

@Test
func deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-deleted-active-reminder-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Prepare the proposal", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(DailyPlanProposal(items: [
        PlannedTask(taskID: "active", title: "Prepare the proposal", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
        PlannedTask(taskID: "next", title: "Send the follow-up", rank: 2, estimateMinutes: 15, reason: "Next", score: 50)
    ], mainObjectiveTaskID: "active", plannedFocusMinutes: 45, availableFocusMinutes: 60), for: day)
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.startSprint(taskID: "active", durationMinutes: 25, now: day)
    try reminders.replace([
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])

    let paused = try agent.snapshot(now: day.addingTimeInterval(300))
    let deletedRow = try #require(paused.taskRows.first(where: { $0.taskID == "active" }))
    #expect(paused.activeTask == nil)
    #expect(deletedRow.title == "Prepare the proposal")
    #expect(deletedRow.state == .paused)
    #expect(deletedRow.elapsedMinutes == 5)
    #expect(deletedRow.latestPauseReason == .reminderDeleted)
    #expect(deletedRow.sprint?.state == .paused)
    #expect(paused.taskRows.contains(where: { $0.taskID == "next" }))

    let repeated = try agent.snapshot(now: day.addingTimeInterval(900))
    #expect(repeated.taskRows.filter { $0.taskID == "active" }.count == 1)
    #expect(repeated.taskRows.first(where: { $0.taskID == "active" })?.elapsedMinutes == 5)

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: day.addingTimeInterval(1_200))
    #expect(restored.activeTask == nil)
    #expect(restored.taskRows.first(where: { $0.taskID == "active" })?.latestPauseReason == .reminderDeleted)
    #expect(restored.taskRows.first(where: { $0.taskID == "active" })?.elapsedMinutes == 5)

    let dismissed = try restarted.apply(.complete, taskID: "active", now: day.addingTimeInterval(1_260))
    #expect(dismissed.taskRows.contains(where: { $0.taskID == "active" }) == false)
}

@Test
func externallyCompletingActiveAppleReminderEndsSessionWithDurableReason() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-external-reminder-completion-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Prepare the proposal", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "active", title: "Prepare the proposal", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
                PlannedTask(taskID: "next", title: "Send the follow-up", rank: 2, estimateMinutes: 15, reason: "Next", score: 50)
            ],
            mainObjectiveTaskID: "active",
            plannedFocusMinutes: 45,
            availableFocusMinutes: 60
        ),
        for: day
    )
    let agent = try TodayDashboardAgent(databaseURL: url)

    _ = try agent.startSprint(taskID: "active", durationMinutes: 25, now: day)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "active",
            title: "Prepare the proposal",
            dueDate: day,
            priority: 9,
            isCompleted: true
        ),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])

    let completed = try agent.snapshot(now: day.addingTimeInterval(300))
    let completedRow = try #require(completed.taskRows.first(where: { $0.taskID == "active" }))
    #expect(completed.activeTask == nil)
    #expect(completedRow.state == .completed)
    #expect(completedRow.elapsedMinutes == 5)
    #expect(completedRow.completionReason == .appleReminderCompleted)
    #expect(completed.taskRows.contains(where: { $0.taskID == "next" }))
    #expect(try ActionOutboxStore(databaseURL: url).recentCommands().contains { $0.entityID == "active" } == false)

    let firstHistory = try #require(
        try TaskHistoryStore(databaseURL: url)
            .completedEntries(for: day)
            .first(where: { $0.taskID == "active" })
    )
    #expect(firstHistory.title == "Prepare the proposal")
    #expect(firstHistory.sourceKind == .reminders)
    #expect(firstHistory.completedAt == day.addingTimeInterval(300))

    let repeated = try agent.snapshot(now: day.addingTimeInterval(900))
    #expect(repeated.taskRows.filter { $0.taskID == "active" }.count == 1)
    #expect(repeated.taskRows.first(where: { $0.taskID == "active" })?.elapsedMinutes == 5)
    #expect(
        try TaskHistoryStore(databaseURL: url)
            .completedEntries(for: day)
            .first(where: { $0.taskID == "active" })?
            .completedAt == firstHistory.completedAt
    )

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: day.addingTimeInterval(1_200))
    let restoredRow = try #require(restored.taskRows.first(where: { $0.taskID == "active" }))
    #expect(restored.activeTask == nil)
    #expect(restoredRow.state == .completed)
    #expect(restoredRow.completionReason == .appleReminderCompleted)
    #expect(restoredRow.elapsedMinutes == 5)
}

@Test
func externallyCompletingUnplannedActiveReminderRestoresReasonWithoutPriorTodaySnapshot() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-unplanned-external-reminder-completion-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Prepare the proposal", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])
    let execution = try TaskExecutionStore(databaseURL: url)
    try execution.startSprint(taskID: "active", durationMinutes: 20, at: day)

    try reminders.replace([
        ReminderSourceSnapshot(
            id: "active",
            title: "Prepare the proposal",
            dueDate: day,
            priority: 9,
            isCompleted: true
        ),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])

    let agent = try TodayDashboardAgent(databaseURL: url)
    let completed = try agent.snapshot(now: day.addingTimeInterval(300))
    let completedRow = try #require(completed.taskRows.first(where: { $0.taskID == "active" }))
    #expect(completed.activeTask == nil)
    #expect(completedRow.title == "Prepare the proposal")
    #expect(completedRow.state == .completed)
    #expect(completedRow.elapsedMinutes == 5)
    #expect(completedRow.completionReason == .appleReminderCompleted)
    #expect(completedRow.sprint == nil)
    #expect(completed.unplannedReminders?.contains(where: { $0.reminderID == "next" }) == true)

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let restored = try restarted.snapshot(now: day.addingTimeInterval(1_200))
    let restoredRow = try #require(restored.taskRows.first(where: { $0.taskID == "active" }))
    #expect(restoredRow.title == "Prepare the proposal")
    #expect(restoredRow.completionReason == .appleReminderCompleted)
    #expect(restoredRow.elapsedMinutes == 5)
}

@Test
func externallyCompletedReminderHistoryIsNotRecordedTwiceByTodayRefresh() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-external-completion-history-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Prepare the proposal", dueDate: day, priority: 9)
    ])
    try TaskExecutionStore(databaseURL: url).apply(.start, taskID: "active", at: day)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "active",
            title: "Prepare the proposal",
            dueDate: day,
            priority: 9,
            isCompleted: true
        )
    ])
    let history = try TaskHistoryStore(databaseURL: url)
    try history.record(
        taskID: "active",
        state: .completed,
        title: "Prepare the proposal",
        sourceKind: .reminders,
        at: day.addingTimeInterval(240)
    )

    let snapshot = try TodayDashboardAgent(databaseURL: url)
        .snapshot(now: day.addingTimeInterval(300))

    #expect(snapshot.taskRows.first(where: { $0.taskID == "active" })?.completionReason == .appleReminderCompleted)
    #expect(try history.evidence(for: ["active"])["active"]?.completionCount == 1)
}

@Test
func completedThenDeletedReminderUsesDurableCompletionHistory() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-completed-then-deleted-reminder-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Prepare the proposal", dueDate: day, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])
    try TaskExecutionStore(databaseURL: url).apply(.start, taskID: "active", at: day)
    try TaskHistoryStore(databaseURL: url).record(
        taskID: "active",
        state: .completed,
        title: "Prepare the proposal",
        sourceKind: .reminders,
        at: day.addingTimeInterval(240)
    )
    try reminders.replace([
        ReminderSourceSnapshot(id: "next", title: "Send the follow-up", dueDate: day, priority: 5)
    ])

    let agent = try TodayDashboardAgent(databaseURL: url)
    let completed = try agent.snapshot(now: day.addingTimeInterval(300))
    let row = try #require(completed.taskRows.first(where: { $0.taskID == "active" }))
    #expect(row.title == "Prepare the proposal")
    #expect(row.state == .completed)
    #expect(row.completionReason == .appleReminderCompleted)
    #expect(row.latestPauseReason == nil)

    let restored = try TodayDashboardAgent(databaseURL: url)
        .snapshot(now: day.addingTimeInterval(1_200))
    #expect(restored.taskRows.first(where: { $0.taskID == "active" })?.completionReason == .appleReminderCompleted)
}

@Test
func agentBoundedSprintRemainsActiveAfterExpiryAndSurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-agent-sprint-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(id: "focus", title: "Write the proposal", dueDate: day, priority: 9)])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "focus", title: "Write the proposal", rank: 1, estimateMinutes: 45, reason: "Main", score: 100)],
            mainObjectiveTaskID: "focus",
            plannedFocusMinutes: 45,
            availableFocusMinutes: 60
        ),
        for: day
    )

    let agent = try TodayDashboardAgent(databaseURL: url)
    let started = try agent.startSprint(taskID: "focus", durationMinutes: 37, now: day)
    #expect(started.activeTask?.sprint?.remainingSeconds == 2_220)

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let afterWake = try restarted.snapshot(now: day.addingTimeInterval(2_500))
    #expect(afterWake.activeTask?.taskID == "focus")
    #expect(afterWake.activeTask?.sprint?.state == .expired)
    #expect(afterWake.taskRows.first?.state == .active)

    let continued = try restarted.apply(.continueOpenEnded, taskID: "focus", now: day.addingTimeInterval(2_500))
    #expect(continued.activeTask?.taskID == "focus")
    #expect(continued.activeTask?.sprint?.state == .continuedOpenEnded)
    #expect(continued.taskRows.first?.state == .active)
}

@Test
func agentBoundedSprintRemainsActiveAfterExpiryAndSurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-agent-sprint-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(id: "focus", title: "Write the proposal", dueDate: day, priority: 9)])
    let plans = try AutonomousPlanStore(databaseURL: url)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "focus", title: "Write the proposal", rank: 1, estimateMinutes: 45, reason: "Main", score: 100)],
            mainObjectiveTaskID: "focus",
            plannedFocusMinutes: 45,
            availableFocusMinutes: 60
        ),
        for: day
    )

    let agent = try TodayDashboardAgent(databaseURL: url)
    let started = try agent.startSprint(taskID: "focus", durationMinutes: 37, now: day)
    #expect(started.activeTask?.sprint?.remainingSeconds == 2_220)

    let restarted = try TodayDashboardAgent(databaseURL: url)
    let afterWake = try restarted.snapshot(now: day.addingTimeInterval(2_500))
    #expect(afterWake.activeTask?.taskID == "focus")
    #expect(afterWake.activeTask?.sprint?.state == .expired)
    #expect(afterWake.taskRows.first?.state == .active)

    let continued = try restarted.apply(.continueOpenEnded, taskID: "focus", now: day.addingTimeInterval(2_500))
    #expect(continued.activeTask?.taskID == "focus")
    #expect(continued.activeTask?.sprint?.state == .continuedOpenEnded)
    #expect(continued.taskRows.first?.state == .active)
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
