import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func taskHistoryStoreCountsPostponementsForFuturePlanning() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-history-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    try store.record(taskID: "proposal", state: .selected)
    try store.record(taskID: "proposal", state: .postponed)
    try store.record(taskID: "proposal", state: .postponed)

    let evidence = try store.evidence(for: ["proposal"])

    #expect(evidence["proposal"]?.deferralCount == 2)
    #expect(evidence["proposal"]?.selectionCount == 1)
}

@Test
func taskHistoryStoreSummarizesTheCompletedAndPostponedDay() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-day-history-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    try store.record(taskID: "proposal", state: .selected, at: day)
    try store.record(taskID: "proposal", state: .completed, at: day)
    try store.record(taskID: "admin", state: .postponed, at: day)

    let summary = try store.summary(for: day)

    #expect(summary.selectedCount == 1)
    #expect(summary.completedCount == 1)
    #expect(summary.postponedCount == 1)
}

@Test
func completedTaskHistoryKeepsReadableLocalEvidenceAcrossRestart() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-completed-history-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3_600)!
    let completedAt = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 16, minute: 45))!

    do {
        let store = try TaskHistoryStore(databaseURL: databaseURL)
        try store.record(
            taskID: "local:proposal",
            state: .completed,
            title: "Finish launch proposal",
            sourceKind: .local,
            at: completedAt
        )
    }

    let reopened = try TaskHistoryStore(databaseURL: databaseURL)
    let entries = try reopened.completedEntries(for: completedAt, calendar: calendar)
    #expect(entries.count == 1)
    #expect(entries[0].taskID == "local:proposal")
    #expect(entries[0].title == "Finish launch proposal")
    #expect(entries[0].sourceKind == .local)
    #expect(entries[0].completedAt == completedAt)
}

@Test
func completedTaskHistoryShowsOneLatestCompletionAndItsLastPauseReason() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-completed-pause-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let completedAt = Date(timeIntervalSince1970: 1_752_332_400)
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    try execute(
        databaseURL,
        "INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES ('reminder-1', 'externalInterruption', '2025-07-12T15:00:00Z', '2025-07-12T15:10:00Z');"
    )
    try store.record(taskID: "reminder-1", state: .completed, title: "Send the report", sourceKind: .reminders, at: completedAt)
    try store.record(taskID: "reminder-1", state: .completed, title: "Send the report", sourceKind: .reminders, at: completedAt.addingTimeInterval(1))

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let entries = try store.completedEntries(for: completedAt, calendar: calendar)
    #expect(entries.count == 1)
    #expect(entries[0].title == "Send the report")
    #expect(entries[0].sourceKind == .reminders)
    #expect(entries[0].lastPauseReason == .externalInterruption)
    #expect(entries[0].completedAt == completedAt.addingTimeInterval(1))
}

@Test
func completedTaskHistoryDoesNotLeakAcrossDayBoundaries() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-completed-boundary-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3_600)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 12))!
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    try store.record(taskID: "previous", state: .completed, title: "Previous", sourceKind: .local, at: calendar.startOfDay(for: day).addingTimeInterval(-1))
    try store.record(taskID: "today", state: .completed, title: "Today", sourceKind: .local, at: calendar.startOfDay(for: day))
    try store.record(taskID: "next", state: .completed, title: "Next", sourceKind: .local, at: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!)

    let entries = try store.completedEntries(for: day, calendar: calendar)
    #expect(entries.map(\.taskID) == ["today"])
}

@Test
func completedTaskRemainsInHistoryWhileExcludedFromTheActiveSourceList() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-completed-active-filter-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let completedAt = Date()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminders.upsertLocal(ReminderSourceSnapshot(
        id: "local:done",
        title: "Finished local task",
        dueDate: nil,
        priority: 0,
        modificationDate: completedAt,
        isCompleted: true,
        sourceKind: .local
    ))
    let history = try TaskHistoryStore(databaseURL: databaseURL)
    try history.record(taskID: "local:done", state: .completed, title: "Finished local task", sourceKind: .local, at: completedAt)

    #expect(try reminders.loadIncomplete().isEmpty)
    #expect(try history.completedEntries(for: completedAt).map(\.title) == ["Finished local task"])
}

private func execute(_ databaseURL: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw TaskHistoryStoreError.openDatabase
    }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw TaskHistoryStoreError.write
    }
}
