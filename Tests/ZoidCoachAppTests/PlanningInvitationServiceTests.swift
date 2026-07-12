import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func planningSnoozeHidesInvitationThenReturnsOnceAndSurvivesRestart() throws {
    let url = planningTestURL("snooze")
    defer { removePlanningTestDatabase(url) }
    let clock = PlanningTestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let ids = PlanningTestIDs(["prompt-1", "response-1", "prompt-2"])
    let store = try PromptInboxStore(
        databaseURL: url,
        now: { clock.now },
        makeID: { ids.next() }
    )
    let service = PlanningInvitationService(store: store, now: { clock.now })
    let first = try store.enqueue(PlanningInvitationPolicy.promptDraft(
        localDay: "2027-01-15",
        itemCount: 2,
        expiresAt: clock.now.addingTimeInterval(86_400)
    )).episode
    let response = try store.respond(
        promptID: first.id,
        action: .snoozePlanning,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .snoozePlanning),
        surface: .dashboard
    )

    let effect = try service.apply(response)
    guard case let .snoozed(until, followUpID) = effect else {
        Issue.record("Expected a snoozed planning invitation")
        return
    }
    #expect(until == clock.now.addingTimeInterval(PlanningInvitationPolicy.snoozeDuration))
    #expect(followUpID == "prompt-2")
    #expect(try store.unresolved().isEmpty)
    #expect(try service.status(
        localDay: "2027-01-15",
        hasPlan: false,
        hasActiveUnplannedTask: false
    ) == PlanningDayStatus(mode: .snoozed, resumesAt: until))

    let reopenedStore = try PromptInboxStore(databaseURL: url, now: { clock.now })
    let reopened = PlanningInvitationService(store: reopenedStore, now: { clock.now })
    #expect(try reopened.status(
        localDay: "2027-01-15",
        hasPlan: false,
        hasActiveUnplannedTask: false
    ).mode == .snoozed)

    clock.advance(by: PlanningInvitationPolicy.snoozeDuration)
    #expect(try reopened.dueFollowUps().map(\.id) == ["prompt-2"])
    _ = try reopened.markPresented("prompt-2")
    #expect(try reopened.dueFollowUps().isEmpty)
    #expect(try reopenedStore.unresolved().map(\.id) == ["prompt-2"])
    #expect(try reopened.status(
        localDay: "2027-01-15",
        hasPlan: false,
        hasActiveUnplannedTask: false
    ).mode == .invitation)
}

@Test
func temporaryPlanningDismissalSuppressesRepeatsUntilItsRecoveryTime() throws {
    let url = planningTestURL("dismiss")
    defer { removePlanningTestDatabase(url) }
    let clock = PlanningTestClock(Date(timeIntervalSince1970: 1_800_100_000))
    let ids = PlanningTestIDs(["prompt-1", "response-1", "prompt-2"])
    let store = try PromptInboxStore(databaseURL: url, now: { clock.now }, makeID: { ids.next() })
    let service = PlanningInvitationService(store: store, now: { clock.now })
    let first = try store.enqueue(PlanningInvitationPolicy.promptDraft(
        localDay: "2027-01-16",
        itemCount: 1,
        expiresAt: clock.now.addingTimeInterval(86_400)
    )).episode
    let response = try store.respond(
        promptID: first.id,
        action: .dismissPlanning,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .dismissPlanning),
        surface: .notification
    )

    _ = try service.apply(response)
    let status = try service.status(
        localDay: "2027-01-16",
        hasPlan: false,
        hasActiveUnplannedTask: false
    )
    #expect(status.mode == .dismissed)
    #expect(status.resumesAt == clock.now.addingTimeInterval(PlanningInvitationPolicy.temporaryDismissDuration))
    #expect(try store.unresolved().isEmpty)

    clock.advance(by: PlanningInvitationPolicy.temporaryDismissDuration)
    #expect(try service.dueFollowUps().count == 1)
}

@Test
func explicitUnplannedChoicePersistsAndGatesDriftUntilWorkStarts() throws {
    let url = planningTestURL("unplanned")
    defer { removePlanningTestDatabase(url) }
    let clock = PlanningTestClock(Date(timeIntervalSince1970: 1_800_200_000))
    let ids = PlanningTestIDs(["prompt-1", "response-1"])
    let store = try PromptInboxStore(databaseURL: url, now: { clock.now }, makeID: { ids.next() })
    let service = PlanningInvitationService(store: store, now: { clock.now })

    _ = try service.beginUnplannedDay(
        localDay: "2027-01-17",
        itemCount: 3,
        expiresAt: clock.now.addingTimeInterval(86_400)
    )
    #expect(try service.status(
        localDay: "2027-01-17",
        hasPlan: false,
        hasActiveUnplannedTask: false
    ) == PlanningDayStatus(mode: .unplanned, driftInterventionsAllowed: false))

    let reopened = PlanningInvitationService(
        store: try PromptInboxStore(databaseURL: url, now: { clock.now }),
        now: { clock.now }
    )
    #expect(try reopened.status(
        localDay: "2027-01-17",
        hasPlan: false,
        hasActiveUnplannedTask: true
    ) == PlanningDayStatus(mode: .unplanned, driftInterventionsAllowed: true))
}

private final class PlanningTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date { lock.withLock { value } }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

private final class PlanningTestIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String { lock.withLock { values.removeFirst() } }
}

private func planningTestURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-planning-\(label)-\(UUID().uuidString).sqlite")
}

private func removePlanningTestDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
