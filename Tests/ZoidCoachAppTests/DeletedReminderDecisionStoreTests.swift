import Foundation
import SQLite3
import Testing
@testable import ZoidCoachInfrastructure

@Test
func deletedReminderBecomesPendingWithoutCopyingNotes() throws {
    let url = deletedReminderDatabaseURL("pending")
    defer { removeDeletedReminderDatabase(url) }
    let store = try ReminderSnapshotStore(databaseURL: url)
    let deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
    let reminder = ReminderSourceSnapshot(
        id: "reminder-1",
        title: "Send proposal",
        dueDate: deletedAt.addingTimeInterval(86_400),
        priority: 5,
        notes: "Private client details at https://secret.example/client",
        listID: "work",
        listName: "Work"
    )
    _ = try store.synchronize([reminder], observedAt: deletedAt.addingTimeInterval(-60))
    _ = try store.synchronize([], observedAt: deletedAt)

    let decision = try #require(store.deletedReminderDecisions().first)
    #expect(decision.sourceID == reminder.id)
    #expect(decision.title == reminder.title)
    #expect(decision.listName == "Work")
    #expect(decision.state == .pending)
    #expect(try store.loadIncomplete().isEmpty)
}

@Test
func failedSourceDeletionRollsBackArchivedDecisionAtomically() throws {
    let url = deletedReminderDatabaseURL("atomic-delete")
    defer { removeDeletedReminderDatabase(url) }
    let store = try ReminderSnapshotStore(databaseURL: url)
    let reminder = ReminderSourceSnapshot(id: "atomic", title: "Atomic task", dueDate: nil, priority: 0)
    _ = try store.synchronize([reminder])
    try executeDeletedReminderSQL(url, """
    CREATE TRIGGER refuse_source_task_delete
    BEFORE DELETE ON source_tasks
    WHEN OLD.source_id = 'atomic'
    BEGIN
        SELECT RAISE(ABORT, 'refuse deletion');
    END;
    """)

    #expect(throws: (any Error).self) {
        try store.synchronize([])
    }
    #expect(try store.deletedReminderDecisions().isEmpty)
    #expect(try store.loadIncomplete().contains { $0.id == reminder.id })
}

@Test
func keepingDeletedReminderIsDurableAndNonDestructive() throws {
    let url = deletedReminderDatabaseURL("keep")
    defer { removeDeletedReminderDatabase(url) }
    let deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
    let store = try ReminderSnapshotStore(databaseURL: url)
    let reminder = ReminderSourceSnapshot(id: "deleted", title: "Deleted task", dueDate: nil, priority: 0)
    let unrelated = ReminderSourceSnapshot(id: "local:other", title: "Unrelated local task", dueDate: nil, priority: 0, sourceKind: .local)
    _ = try store.upsertLocal(unrelated)
    _ = try store.synchronize([reminder])
    _ = try store.synchronize([], observedAt: deletedAt)
    #expect(try store.keepDeletedReminderInLocalHistory(sourceID: reminder.id, decidedAt: deletedAt.addingTimeInterval(10)))

    let reopened = try ReminderSnapshotStore(databaseURL: url)
    let kept = try #require(reopened.deletedReminderDecisions().first)
    #expect(kept.state == .kept)
    #expect(kept.decidedAt == deletedAt.addingTimeInterval(10))
    #expect(try reopened.loadIncomplete().contains { $0.id == unrelated.id })
}

@Test
func reappearingReminderClearsOnlyItsMatchingDeletedDecision() throws {
    let url = deletedReminderDatabaseURL("reappear")
    defer { removeDeletedReminderDatabase(url) }
    let store = try ReminderSnapshotStore(databaseURL: url)
    let first = ReminderSourceSnapshot(id: "first", title: "First", dueDate: nil, priority: 0)
    let second = ReminderSourceSnapshot(id: "second", title: "Second", dueDate: nil, priority: 0)
    _ = try store.synchronize([first, second])
    _ = try store.synchronize([])
    #expect(try store.deletedReminderDecisions().count == 2)
    #expect(try store.keepDeletedReminderInLocalHistory(sourceID: first.id))

    _ = try store.synchronize([first])

    #expect(try store.deletedReminderDecisions().map(\.sourceID) == [second.id])
}

@Test
func removingLocalCopyDeletesOnlyTheConfirmedDecision() throws {
    let url = deletedReminderDatabaseURL("remove")
    defer { removeDeletedReminderDatabase(url) }
    let store = try ReminderSnapshotStore(databaseURL: url)
    let first = ReminderSourceSnapshot(id: "first", title: "First", dueDate: nil, priority: 0)
    let second = ReminderSourceSnapshot(id: "second", title: "Second", dueDate: nil, priority: 0)
    _ = try store.synchronize([first, second])
    _ = try store.synchronize([])

    #expect(try store.keepDeletedReminderInLocalHistory(sourceID: first.id))
    #expect(try store.removeDeletedReminderLocalCopy(sourceID: first.id) == false)
    #expect(try store.removeDeletedReminderLocalCopy(sourceID: second.id))

    let remaining = try store.deletedReminderDecisions()
    #expect(remaining.map(\.sourceID) == [first.id])
    #expect(remaining.first?.state == .kept)
}

private func deletedReminderDatabaseURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-deleted-reminder-\(label)-\(UUID().uuidString).sqlite")
}

private func removeDeletedReminderDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private func executeDeletedReminderSQL(_ url: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw DeletedReminderSQLTestError.open
    }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw DeletedReminderSQLTestError.execute
    }
}

private enum DeletedReminderSQLTestError: Error {
    case open
    case execute
}
