import Foundation
import Testing
import ZoidCoachInfrastructure

@Test func notificationDeliveryLedgerRecordsTruthfulReplacementWithoutMessageContent() throws {
    let fixture = NotificationDeliveryLedgerFixture()
    defer { fixture.cleanUp() }
    let clock = NotificationLedgerTestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.databaseURL, now: clock.now)

    let first = try ledger.record(
        requestIdentifier: "qa.prompt.same-decision",
        promptID: "prompt-1",
        category: "PLAN_READY",
        outcome: .acceptedBySystem
    )
    clock.advance(by: 10)
    let second = try ledger.record(
        requestIdentifier: "qa.prompt.same-decision",
        promptID: "prompt-1",
        category: "PLAN_READY",
        outcome: .acceptedBySystem
    )

    #expect(first.attempt == 1)
    #expect(!first.replacedPriorRequest)
    #expect(second.attempt == 2)
    #expect(second.replacedPriorRequest)
    #expect(try ledger.recent().map(\.id) == [second.id, first.id])
}

@Test func notificationDeliveryLedgerDistinguishesFallbackFailureAcceptanceAndDelivery() throws {
    let fixture = NotificationDeliveryLedgerFixture()
    defer { fixture.cleanUp() }
    let clock = NotificationLedgerTestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.databaseURL, now: clock.now)

    for (index, outcome) in NotificationDeliveryOutcome.allCases.enumerated() {
        clock.advance(by: 1)
        _ = try ledger.record(
            requestIdentifier: "request-\(index)",
            promptID: "prompt-\(index)",
            category: "ONBOARDING_TEST",
            outcome: outcome,
            error: outcome == .schedulingFailed
                ? "failed at /Users/person/private.txt for person@example.com\nretry"
                : nil
        )
    }

    let records = try ledger.recent()
    #expect(Set(records.map(\.outcome)) == Set(NotificationDeliveryOutcome.allCases))
    let failure = try #require(records.first(where: { $0.outcome == .schedulingFailed }))
    #expect(failure.redactedError?.contains("/Users/person") == false)
    #expect(failure.redactedError?.contains("person@example.com") == false)
    #expect(failure.redactedError?.contains("\n") == false)
}

@Test func notificationDeliveryLedgerRetentionIsBoundedAndRestartSafe() throws {
    let fixture = NotificationDeliveryLedgerFixture()
    defer { fixture.cleanUp() }
    let clock = NotificationLedgerTestClock(Date(timeIntervalSince1970: 1_800_000_000))
    var ledger: NotificationDeliveryLedger? = try NotificationDeliveryLedger(
        databaseURL: fixture.databaseURL,
        now: clock.now
    )
    _ = try ledger?.record(
        requestIdentifier: "expired",
        promptID: "expired-prompt",
        category: "PLAN_READY",
        outcome: .acceptedBySystem
    )
    clock.advance(by: 31 * 86_400)
    _ = try ledger?.record(
        requestIdentifier: "current",
        promptID: "current-prompt",
        category: "PLAN_CHANGED",
        outcome: .authorizationUnavailable
    )
    #expect(try ledger?.enforceRetention() == 1)
    ledger = nil

    let reopened = try NotificationDeliveryLedger(databaseURL: fixture.databaseURL, now: clock.now)
    let records = try reopened.recent()
    #expect(records.map(\.requestIdentifier) == ["current"])
}

@Test func notificationDeliveryLedgerRejectsEmptyAndBoundsIdentifiers() throws {
    let fixture = NotificationDeliveryLedgerFixture()
    defer { fixture.cleanUp() }
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.databaseURL)

    #expect(throws: NotificationDeliveryLedgerError.invalidRecord) {
        try ledger.record(
            requestIdentifier: " ",
            promptID: "prompt",
            category: "PLAN_READY",
            outcome: .acceptedBySystem
        )
    }
    let record = try ledger.record(
        requestIdentifier: String(repeating: "r", count: 500),
        promptID: String(repeating: "p", count: 500),
        category: String(repeating: "c", count: 500),
        outcome: .acceptedBySystem
    )
    #expect(record.requestIdentifier.count == 240)
    #expect(record.promptID.count == 240)
    #expect(record.category.count == 240)
}

@Test func notificationDeliveryHistoryParticipatesInDateRangePrivacyDeletion() throws {
    let fixture = NotificationDeliveryLedgerFixture()
    defer { fixture.cleanUp() }
    let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = NotificationLedgerTestClock(firstDate)
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.databaseURL, now: clock.now)
    _ = try ledger.record(
        requestIdentifier: "first",
        promptID: "first-prompt",
        category: "PLAN_READY",
        outcome: .acceptedBySystem
    )
    clock.advance(by: 2 * 86_400)
    _ = try ledger.record(
        requestIdentifier: "second",
        promptID: "second-prompt",
        category: "PLAN_CHANGED",
        outcome: .authorizationUnavailable
    )

    let privacy = try PrivacyDataService(databaseURL: fixture.databaseURL)
    _ = try privacy.deleteDateRange(
        start: firstDate.addingTimeInterval(-1),
        end: firstDate.addingTimeInterval(86_400)
    )

    #expect(try ledger.recent().map(\.requestIdentifier) == ["second"])
}

private struct NotificationDeliveryLedgerFixture {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-notification-ledger-\(UUID().uuidString).sqlite")

    func cleanUp() {
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("shm"))
    }
}

private final class NotificationLedgerTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}
