import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func reminderSnapshotStoreMakesForegroundReminderDataAvailableToTheBackgroundAgent() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-snapshot-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ReminderSnapshotStore(databaseURL: databaseURL)
    let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders = [
        ReminderSourceSnapshot(
            id: "proposal",
            title: "Send proposal",
            dueDate: dueDate,
            priority: 9
        )
    ]

    try store.replace(reminders)

    #expect(try store.loadIncomplete() == reminders)
}

@Test
func reminderSynchronizationEmitsOnlyRealChangesAndPreservesEventKitPriorityMeaning() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-snapshot-diff-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ReminderSnapshotStore(databaseURL: databaseURL)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = ReminderSourceSnapshot(id: "urgent", title: "Urgent", dueDate: date, priority: 1, notes: "Client", listID: "work", listName: "Work", modificationDate: date)

    let first = try store.synchronize([reminder], observedAt: date, timeZone: TimeZone(identifier: "UTC")!)
    let second = try store.synchronize([reminder], observedAt: date.addingTimeInterval(60), timeZone: TimeZone(identifier: "UTC")!)
    let updated = ReminderSourceSnapshot(id: "urgent", title: "Urgent now", dueDate: date, priority: 1, notes: "Client", listID: "work", listName: "Work", modificationDate: date.addingTimeInterval(60))
    let third = try store.synchronize([updated], observedAt: date.addingTimeInterval(60), timeZone: TimeZone(identifier: "UTC")!)
    let audit = try DomainEventStore(databaseURL: databaseURL).events()

    #expect(first.insertedCount == 1)
    #expect(second.unchangedCount == 1)
    #expect(third.updatedCount == 1)
    #expect(audit.filter { $0.type.hasPrefix("source_task.") }.count == 2)
    #expect(ReminderPriority.fromEventKit(1) == .high)
    #expect(ReminderPriority.fromEventKit(5) == .medium)
    #expect(ReminderPriority.fromEventKit(9) == .low)
}
