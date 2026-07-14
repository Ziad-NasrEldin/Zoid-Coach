import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func operationKeySurvivesStoreRelaunchAndReceiptsAreIdempotent() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-operation")
    defer { removeDatabaseFiles(at: databaseURL) }
    let id = UUID()
    let requestedAt = Date(timeIntervalSince1970: 1_752_489_600)

    do {
        let store = try TaskMutationOperationStore(databaseURL: databaseURL)
        let operation = try store.begin(id: id, taskID: "task-1", command: .complete, requestedAt: requestedAt)
        #expect(operation.state == .pending)
        try store.completeStep(operationID: id, step: "execution", at: requestedAt)
        try store.completeStep(operationID: id, step: "execution", at: requestedAt)
    }

    let reopened = try TaskMutationOperationStore(databaseURL: databaseURL)
    #expect(try reopened.load(id: id)?.requestedAt == requestedAt)
    #expect(try reopened.hasCompletedStep(operationID: id, step: "execution"))
}

@Test
func reusedOperationKeyCannotChangeItsMutation() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-conflict")
    defer { removeDatabaseFiles(at: databaseURL) }
    let store = try TaskMutationOperationStore(databaseURL: databaseURL)
    let id = UUID()
    _ = try store.begin(id: id, taskID: "task-1", command: .complete, requestedAt: Date())

    #expect(throws: TaskMutationOperationStoreError.operationKeyConflict) {
        try store.begin(id: id, taskID: "task-2", command: .start, requestedAt: Date())
    }

    let blockID = UUID()
    _ = try store.begin(id: blockID, taskID: "task-1", command: .block, blockedReason: "Waiting for design", requestedAt: Date())
    #expect(throws: TaskMutationOperationStoreError.operationKeyConflict) {
        try store.begin(id: blockID, taskID: "task-1", command: .block, blockedReason: "Waiting for approval", requestedAt: Date())
    }
}

@Test
func terminalValidationStateSurvivesRelaunchWithoutAReceipt() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-validation")
    defer { removeDatabaseFiles(at: databaseURL) }
    let id = UUID()
    let store = try TaskMutationOperationStore(databaseURL: databaseURL)
    _ = try store.begin(id: id, taskID: "task-1", command: .block, requestedAt: Date())
    try store.failValidation(operationID: id, diagnostic: "Explain the blocker.")

    let reopened = try TaskMutationOperationStore(databaseURL: databaseURL)
    #expect(try reopened.load(id: id)?.state == .failed)
    #expect(try reopened.load(id: id)?.lastDiagnostic == "Explain the blocker.")
}

@Test
func executionSideEffectAndReceiptCommitExactlyOnce() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-execution")
    defer { removeDatabaseFiles(at: databaseURL) }
    let operationID = UUID()
    let requestedAt = Date(timeIntervalSince1970: 1_752_489_600)
    let operations = try TaskMutationOperationStore(databaseURL: databaseURL)
    _ = try operations.begin(id: operationID, taskID: "task-1", command: .start, requestedAt: requestedAt)
    let execution = try TaskExecutionStore(databaseURL: databaseURL)

    try execution.apply(.start, taskID: "task-1", operationID: operationID, at: requestedAt)
    try execution.apply(.start, taskID: "task-1", operationID: operationID, at: requestedAt)

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = 'task-1';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_steps WHERE operation_id = '\(operationID.uuidString)' AND step = 'execution';") == 1)
}

@Test
func historySideEffectUsesOperationKeyAsRawStorageIdempotencyGuard() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-history")
    defer { removeDatabaseFiles(at: databaseURL) }
    let operationID = UUID()
    let store = try TaskHistoryStore(databaseURL: databaseURL)

    try store.record(taskID: "task-1", state: .completed, operationID: operationID)
    try store.record(taskID: "task-1", state: .completed, operationID: operationID)

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE operation_id = '\(operationID.uuidString)';") == 1)
}

@Test(arguments: ["execution", "reminder-completion", "history", "reward", "learning", "today-snapshot"])
func relaunchAfterEachCompletionStepResumesWithoutDuplicatingRawHistory(failingStep: String) throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-resume-\(failingStep)")
    defer { removeDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_752_489_600)
    let operationID = UUID()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminders.createLocal(
        ReminderSourceSnapshot(id: "task-1", title: "Finish report", dueDate: now, priority: 9, sourceKind: .local),
        observedAt: now
    )
    let plans = try AutonomousPlanStore(databaseURL: databaseURL)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "task-1", title: "Finish report", rank: 1, estimateMinutes: 30, reason: "Due", score: 100)],
            mainObjectiveTaskID: "task-1",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: now
    )
    let failingAgent = try TodayDashboardAgent(databaseURL: databaseURL, mutationStepObserver: { step in
        if step == failingStep { throw MutationTestFailure.injected }
    })
    _ = try failingAgent.snapshot(now: now)

    #expect(throws: MutationTestFailure.injected) {
        try failingAgent.apply(.complete, taskID: "task-1", operationID: operationID, now: now)
    }
    let relaunchedAgent = try TodayDashboardAgent(databaseURL: databaseURL)
    _ = try relaunchedAgent.apply(.complete, taskID: "task-1", operationID: operationID, now: now)

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE operation_id = '\(operationID.uuidString)' AND state = 'completed';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_operations WHERE operation_id = '\(operationID.uuidString)' AND state = 'completed';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM learning_samples WHERE id = 'task-completion:task-1:\(Int(now.timeIntervalSince1970))';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM gaming_reward_ledger WHERE task_id = 'task-1';") == 1)
}

@Test
func relaunchAfterPlanPromotionReceiptDoesNotRepeatBlockExecution() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-block-resume")
    defer { removeDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_752_489_600)
    let operationID = UUID()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "blocked", title: "Blocked task", dueDate: now, priority: 9),
        ReminderSourceSnapshot(id: "next", title: "Next task", dueDate: now, priority: 5)
    ])
    let plans = try AutonomousPlanStore(databaseURL: databaseURL)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "blocked", title: "Blocked task", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
                PlannedTask(taskID: "next", title: "Next task", rank: 2, estimateMinutes: 20, reason: "Next", score: 80)
            ],
            mainObjectiveTaskID: "blocked",
            plannedFocusMinutes: 50,
            availableFocusMinutes: 60
        ),
        for: now
    )
    let failingAgent = try TodayDashboardAgent(databaseURL: databaseURL, mutationStepObserver: { step in
        if step == "plan-promotion" { throw MutationTestFailure.injected }
    })

    #expect(throws: MutationTestFailure.injected) {
        try failingAgent.apply(.block, taskID: "blocked", blockedReason: "Waiting for approval", operationID: operationID, now: now)
    }
    let snapshot = try TodayDashboardAgent(databaseURL: databaseURL).apply(
        .block,
        taskID: "blocked",
        blockedReason: "Waiting for approval",
        operationID: operationID,
        now: now
    )

    #expect(snapshot.mainObjective == "Next task")
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_pause_events WHERE task_id = 'blocked' AND reason = 'blocked';") == 1)
}

@Test
func relaunchAfterOutboxReceiptDoesNotDuplicateReminderCommand() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-outbox-resume")
    defer { removeDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_752_489_600)
    let operationID = UUID()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "reminder-1", title: "Complete Reminder", dueDate: now, priority: 9)
    ])
    let failingAgent = try TodayDashboardAgent(databaseURL: databaseURL, mutationStepObserver: { step in
        if step == "outbox" { throw MutationTestFailure.injected }
    })
    _ = try failingAgent.snapshot(now: now)

    #expect(throws: MutationTestFailure.injected) {
        try failingAgent.apply(.complete, taskID: "reminder-1", operationID: operationID, now: now)
    }
    _ = try TodayDashboardAgent(databaseURL: databaseURL).apply(
        .complete,
        taskID: "reminder-1",
        operationID: operationID,
        now: now
    )

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM action_commands WHERE entity_id = 'reminder-1' AND action_type = 'completeReminder';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE operation_id = '\(operationID.uuidString)' AND state = 'completed';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_operations WHERE operation_id = '\(operationID.uuidString)' AND state = 'completed';") == 1)
}

@Test
func persistentDatabaseLockStopsBeforeCreatingAnOperationOrSideEffect() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-persistent-lock")
    defer { removeDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_752_489_600)
    let operationID = UUID()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "reminder-1", title: "Locked Reminder", dueDate: now, priority: 9)
    ])
    let agent = try TodayDashboardAgent(databaseURL: databaseURL, mutationLockRetryDelays: [0.01, 0.02])
    var rawBlocker: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &rawBlocker, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
    let blocker = try #require(rawBlocker)
    defer {
        _ = sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil)
        sqlite3_close(blocker)
    }
    #expect(sqlite3_exec(blocker, "BEGIN EXCLUSIVE TRANSACTION;", nil, nil, nil) == SQLITE_OK)

    #expect(throws: TodayDashboardAgentError.databaseTemporarilyLocked) {
        try agent.apply(.complete, taskID: "reminder-1", operationID: operationID, now: now)
    }
    #expect(sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil) == SQLITE_OK)

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_operations WHERE operation_id = '\(operationID.uuidString)';") == 0)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM action_commands WHERE entity_id = 'reminder-1';") == 0)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE task_id = 'reminder-1';") == 0)
}

@Test
func temporaryDatabaseLockRetriesTheSameOperationExactlyOnce() async throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-temporary-lock")
    defer { removeDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_752_489_600)
    let operationID = UUID()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "reminder-1", title: "Temporarily locked", dueDate: now, priority: 9)
    ])
    let agent = try TodayDashboardAgent(databaseURL: databaseURL, mutationLockRetryDelays: [0.05, 0.10, 0.20])
    var rawBlocker: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &rawBlocker, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
    let blocker = try #require(rawBlocker)
    defer { sqlite3_close(blocker) }
    #expect(sqlite3_exec(blocker, "BEGIN EXCLUSIVE TRANSACTION;", nil, nil, nil) == SQLITE_OK)

    let completion = Task.detached {
        try agent.apply(.complete, taskID: "reminder-1", operationID: operationID, now: now)
    }
    try await Task.sleep(for: .milliseconds(40))
    #expect(sqlite3_exec(blocker, "COMMIT;", nil, nil, nil) == SQLITE_OK)
    _ = try await completion.value

    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_operations WHERE operation_id = '\(operationID.uuidString)' AND state = 'completed';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM action_commands WHERE entity_id = 'reminder-1' AND action_type = 'completeReminder';") == 1)
    #expect(try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE operation_id = '\(operationID.uuidString)';") == 1)
}

private func temporaryDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-\(name)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("zoid.sqlite")
}

private func removeDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

private func scalarCount(_ databaseURL: URL, _ sql: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw TaskMutationOperationStoreError.openDatabase }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskMutationOperationStoreError.read }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw TaskMutationOperationStoreError.read }
    return Int(sqlite3_column_int(statement, 0))
}

private enum MutationTestFailure: Error, Equatable { case injected }
