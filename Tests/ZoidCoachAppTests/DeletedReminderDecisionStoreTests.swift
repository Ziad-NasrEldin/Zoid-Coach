import Foundation
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
        notes: "Private client details",
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

    #expect(try store.removeDeletedReminderLocalCopy(sourceID: first.id))
    #expect(try store.deletedReminderDecisions().map(\.sourceID) == [second.id])
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
