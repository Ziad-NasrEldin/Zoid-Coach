import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func outboxDeduplicatesEquivalentDesiredActions() throws {
    let url = temporaryOutboxURL("dedupe")
    defer { removeOutboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try ActionOutboxStore(databaseURL: url, now: { date })
    let desired = ActionDesiredState.reminder(ReminderDesiredState(priority: 9, metadataMarker: "zoid:v1"))

    let first = try store.enqueue(type: .setReminderPriority, entityID: "reminder-1", desiredState: desired, planVersion: 1)
    let second = try store.enqueue(type: .setReminderPriority, entityID: "reminder-1", desiredState: desired, planVersion: 1)

    #expect(first.wasInserted)
    #expect(second.wasInserted == false)
    #expect(first.command.id == second.command.id)
    #expect(try store.recentCommands().count == 1)
}

@Test
func leavingAutomaticModeCancelsOnlyUnapprovedPlanWrites() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-origin-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try ActionOutboxStore(databaseURL: url)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let automatic = try store.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "automatic",
        desiredState: .calendarBlock(CalendarBlockDesiredState(title: "Auto", start: start, end: start.addingTimeInterval(1_800), ownershipToken: "auto", planItemID: "automatic")),
        planVersion: 1,
        origin: .automaticPlan
    )
    let approved = try store.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "approved",
        desiredState: .calendarBlock(CalendarBlockDesiredState(title: "Approved", start: start, end: start.addingTimeInterval(1_800), ownershipToken: "approved", planItemID: "approved")),
        planVersion: 1,
        origin: .approvedPlan
    )

    let claim = try store.claimNextReady()
    #expect(claim?.id == approved.command.id)
    #expect(try store.cancelPendingAutomaticPlanCommands() == 1)
    #expect(try store.command(commandID: automatic.command.id)?.state == .cancelled)
    #expect(try store.command(commandID: approved.command.id)?.state == .executing)
}

@Test
func retryableActionResumesOnceAndRetainsAttemptHistory() throws {
    let url = temporaryOutboxURL("retry")
    defer { removeOutboxDatabase(url) }
    let clock = OutboxTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = try ActionOutboxStore(databaseURL: url, now: { clock.now })
    let desired = ActionDesiredState.calendarBlock(CalendarBlockDesiredState(
        title: "Focus",
        start: clock.now.addingTimeInterval(3_600),
        end: clock.now.addingTimeInterval(5_400),
        ownershipToken: "owned-1",
        planItemID: "item-1"
    ))
    _ = try store.enqueue(type: .createCalendarBlock, entityID: "item-1", desiredState: desired, planVersion: 2)
    let firstClaimValue = try store.claimNextReady()
    let firstClaim = try #require(firstClaimValue)
    let retryAt = clock.now.addingTimeInterval(60)
    try store.markFailed(firstClaim, retryable: true, redactedError: "Calendar temporarily unavailable", retryAt: retryAt)

    #expect(try store.claimNextReady() == nil)
    clock.advance(by: 61)
    let secondClaimValue = try store.claimNextReady()
    let secondClaim = try #require(secondClaimValue)
    try store.markSucceeded(secondClaim, platformIdentifier: "event-1")
    let attempts = try store.attempts(commandID: secondClaim.id)

    #expect(secondClaim.attemptCount == 2)
    #expect(attempts.map(\.state) == [.retryableFailure, .succeeded])
    #expect(attempts.last?.platformIdentifier == "event-1")
    #expect(try store.claimNextReady() == nil)
    let audit = try DomainEventStore(databaseURL: url).events()
    #expect(audit.contains { $0.type == "action.enqueued" })
    #expect(audit.contains { $0.type == "action.retryable_failure" })
    #expect(audit.contains { $0.type == "action.succeeded" })
}

@Test
func executingCommandsRemainVisibleForCrashReconciliation() throws {
    let url = temporaryOutboxURL("recovery")
    defer { removeOutboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try ActionOutboxStore(databaseURL: url, now: { date })
    _ = try store.enqueue(type: .completeReminder, entityID: "task", desiredState: .completeReminder, planVersion: 1)

    let claimedValue = try store.claimNextReady()
    let claimed = try #require(claimedValue)
    let recovered = try store.executingCommands()

    #expect(recovered == [claimed])
    #expect(try store.attempts(commandID: claimed.id).map(\.state) == [.executing])
}

@Test
func supersedingEnqueueAtomicallyCancelsAnOlderRetryableCommand() throws {
    let url = temporaryOutboxURL("supersede")
    defer { removeOutboxDatabase(url) }
    let clock = OutboxTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = try ActionOutboxStore(databaseURL: url, now: { clock.now })
    let firstDesired = ActionDesiredState.calendarBlock(CalendarBlockDesiredState(
        title: "Focus",
        start: clock.now.addingTimeInterval(3_600),
        end: clock.now.addingTimeInterval(5_400),
        ownershipToken: "owned-1",
        planItemID: "item-1"
    ))
    let first = try store.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "item-1",
        desiredState: firstDesired,
        planVersion: 1,
        supersedingPending: true
    ).command
    let claimedValue = try store.claimNextReady()
    let claimed = try #require(claimedValue)
    try store.markFailed(claimed, retryable: true, redactedError: "temporary", retryAt: clock.now)

    let secondDesired = ActionDesiredState.calendarBlock(CalendarBlockDesiredState(
        title: "Focus",
        start: clock.now.addingTimeInterval(7_200),
        end: clock.now.addingTimeInterval(9_000),
        ownershipToken: "owned-1",
        planItemID: "item-1"
    ))
    let second = try store.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "item-1",
        desiredState: secondDesired,
        planVersion: 2,
        supersedingPending: true
    ).command
    _ = try store.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "item-1",
        desiredState: firstDesired,
        planVersion: 1,
        supersedingPending: true
    )

    #expect(try store.command(commandID: first.id)?.state == .cancelled)
    #expect(try store.command(commandID: second.id)?.state == .pending)
    #expect(try store.claimNextReady()?.id == second.id)
    #expect(try DomainEventStore(databaseURL: url).events().contains { $0.type == "action.superseded" })
}

@Test
func oneOutboxStoreSerializesConcurrentEnqueues() async throws {
    let url = temporaryOutboxURL("concurrent")
    defer { removeOutboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try ActionOutboxStore(databaseURL: url, now: { date })
    let desired = ActionDesiredState.reminder(ReminderDesiredState(priority: 1, metadataMarker: "same"))

    let insertedCount = try await withThrowingTaskGroup(of: Bool.self) { group in
        for _ in 0..<32 {
            group.addTask {
                try store.enqueue(
                    type: .setReminderPriority,
                    entityID: "shared-reminder",
                    desiredState: desired,
                    planVersion: 1
                ).wasInserted
            }
        }
        var insertedCount = 0
        for try await inserted in group where inserted { insertedCount += 1 }
        return insertedCount
    }

    #expect(insertedCount == 1)
    #expect(try store.recentCommands().count == 1)
}

private final class OutboxTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ date: Date) { stored = date }

    var now: Date { lock.withLock { stored } }

    func advance(by interval: TimeInterval) {
        lock.withLock { stored = stored.addingTimeInterval(interval) }
    }
}

private func temporaryOutboxURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("zoid-outbox-\(label)-\(UUID().uuidString).sqlite")
}

private func removeOutboxDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
}
