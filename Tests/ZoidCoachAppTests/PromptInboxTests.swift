import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func promptEpisodeStateMachineEnforcesTheDocumentedLifecycle() throws {
    let stateMachine = PromptEpisodeStateMachine()

    #expect(try stateMachine.transition(from: .detected, on: .queue) == .queued)
    #expect(try stateMachine.transition(from: .queued, on: .present) == .presented)
    #expect(try stateMachine.transition(from: .presented, on: .respond) == .responded)
    #expect(try stateMachine.transition(from: .queued, on: .dismiss) == .dismissed)
    #expect(throws: PromptStateMachineError.invalidTransition(from: .responded, event: .present)) {
        try stateMachine.transition(from: .responded, on: .present)
    }
}

@Test
func promptInboxSerializesConcurrentResponseDelivery() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-concurrency-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try PromptInboxStore(databaseURL: url)
    let episode = try store.enqueue(PromptDraft(
        decisionKey: "concurrent",
        type: "PLAN_READY",
        title: "Plan",
        summary: "Ready",
        actions: [PromptAction(kind: .acceptPlan, title: "Accept")]
    )).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .acceptPlan)

    let appliedCount = try await withThrowingTaskGroup(of: Bool.self) { group in
        for _ in 0..<20 {
            group.addTask {
                try store.respond(promptID: episode.id, action: .acceptPlan, actionToken: token, surface: .notification).wasApplied
            }
        }
        var count = 0
        for try await applied in group where applied { count += 1 }
        return count
    }

    #expect(appliedCount == 1)
    #expect(try store.responses(promptID: episode.id).count == 1)
    #expect(try store.pendingEffects().count == 1)
}

@Test
func promptResponseTokensAreStableAndBoundToOnePromptActionPair() {
    let first = PromptResponseToken.make(promptID: "prompt-1", action: .startShortSprint)

    #expect(first == "b965619892eb37f5b454bf4a9f382ac5c20b388d8da5507b972958b5557dc4f5")
    #expect(PromptResponseToken.make(promptID: "prompt-1", action: .startShortSprint) == first)
    #expect(PromptResponseToken.make(promptID: "prompt-1", action: .ignore) != first)
    #expect(PromptResponseToken.make(promptID: "prompt-2", action: .startShortSprint) != first)
}

@Test
func promptInboxKeepsOnlyOneUnresolvedEpisodePerDecision() throws {
    let url = temporaryPromptInboxURL("one-decision")
    defer { removePromptInboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let ids = PromptInboxIDSequence(["prompt-1", "prompt-2"])
    let store = try PromptInboxStore(databaseURL: url, now: { date }, makeID: { ids.next() })
    let draft = promptDraft(decisionKey: "drift:gaming")

    let first = try store.enqueue(draft)
    let second = try store.enqueue(draft)

    #expect(first.wasInserted)
    #expect(second.wasInserted == false)
    #expect(first.episode.id == second.episode.id)
    #expect(try store.unresolved() == [first.episode])
}

@Test
func promptResponseIsAppliedExactlyOnceAcrossRepeatedSurfaceDelivery() throws {
    let url = temporaryPromptInboxURL("idempotent-response")
    defer { removePromptInboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let ids = PromptInboxIDSequence(["prompt-1", "response-1", "prompt-2"])
    let store = try PromptInboxStore(databaseURL: url, now: { date }, makeID: { ids.next() })
    let first = try store.enqueue(promptDraft(decisionKey: "meeting:abc")).episode
    let token = PromptResponseToken.make(promptID: first.id, action: .addMeeting)

    let applied = try store.respond(promptID: first.id, action: .addMeeting, actionToken: token, surface: .dashboard)
    let replay = try store.respond(promptID: first.id, action: .addMeeting, actionToken: token, surface: .notification)
    let next = try store.enqueue(promptDraft(decisionKey: "meeting:abc"))

    #expect(applied.wasApplied)
    #expect(applied.episode.state == .responded)
    #expect(replay.wasApplied == false)
    #expect(replay.response == applied.response)
    #expect(try store.responses(promptID: first.id).count == 1)
    #expect(try store.pendingEffects() == [PromptResponseResult(
        response: applied.response,
        episode: applied.episode,
        wasApplied: false
    )])
    try store.markEffectApplied(responseID: applied.response.id)
    try store.markEffectApplied(responseID: applied.response.id)
    #expect(try store.pendingEffects().isEmpty)
    #expect(next.wasInserted)
    #expect(next.episode.id == "prompt-2")
}

@Test
func promptResponseAndPendingEffectAreCommittedAtomically() throws {
    let url = temporaryPromptInboxURL("durable-effect")
    defer { removePromptInboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let ids = PromptInboxIDSequence(["prompt-1", "response-1"])
    let store = try PromptInboxStore(databaseURL: url, now: { date }, makeID: { ids.next() })
    let episode = try store.enqueue(promptDraft(decisionKey: "meeting:durable")).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .ignore)

    let response = try store.respond(
        promptID: episode.id,
        action: .ignore,
        actionToken: token,
        surface: .notification
    )

    let reopened = try PromptInboxStore(databaseURL: url, now: { date })
    #expect(try reopened.pendingEffects() == [PromptResponseResult(
        response: response.response,
        episode: response.episode,
        wasApplied: false
    )])
}

@Test
func expiredPromptReleasesItsDecisionForANewEpisode() throws {
    let url = temporaryPromptInboxURL("expiry")
    defer { removePromptInboxDatabase(url) }
    let clock = PromptInboxTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let ids = PromptInboxIDSequence(["prompt-1", "prompt-2"])
    let store = try PromptInboxStore(databaseURL: url, now: { clock.now }, makeID: { ids.next() })
    let first = try store.enqueue(promptDraft(
        decisionKey: "plan:ready",
        expiresAt: clock.now.addingTimeInterval(60)
    )).episode

    clock.advance(by: 61)
    #expect(try store.unresolved().isEmpty)
    #expect(try store.episode(promptID: first.id)?.state == .timedOut)
    #expect(try store.enqueue(promptDraft(decisionKey: "plan:ready")).wasInserted)
}

@Test
func promptInboxRejectsATokenBoundToAnotherAction() throws {
    let url = temporaryPromptInboxURL("token-binding")
    defer { removePromptInboxDatabase(url) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try PromptInboxStore(databaseURL: url, now: { date }, makeID: { "prompt-1" })
    let episode = try store.enqueue(promptDraft(decisionKey: "meeting:xyz")).episode
    let wrongToken = PromptResponseToken.make(promptID: episode.id, action: .ignore)

    #expect(throws: PromptInboxStoreError.invalidActionToken) {
        try store.respond(promptID: episode.id, action: .addMeeting, actionToken: wrongToken, surface: .dashboard)
    }
    #expect(try store.episode(promptID: episode.id)?.state == .queued)
    #expect(try store.responses(promptID: episode.id).isEmpty)
}

@Test
func promptInboxTimelineSeparatesWaitingSnoozedAndRecentChoicesAcrossRestart() throws {
    let url = temporaryPromptInboxURL("timeline-restart")
    defer { removePromptInboxDatabase(url) }
    let clock = PromptInboxTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let ids = PromptInboxIDSequence(["prompt-1", "prompt-2", "response-1", "prompt-3"])
    let store = try PromptInboxStore(databaseURL: url, now: { clock.now }, makeID: { ids.next() })
    let first = try store.enqueue(promptDraft(decisionKey: "drift:same")).episode
    let snoozeUntil = clock.now.addingTimeInterval(300)
    let snoozed = try store.enqueue(PromptDraft(
        decisionKey: "planning:snoozed",
        type: "PLAN_READY",
        title: "Plan when ready",
        summary: "This choice will return later.",
        actions: [PromptAction(kind: .reviewPlan, title: "Review")],
        payload: ["notBefore": ISO8601DateFormatter().string(from: snoozeUntil)]
    )).episode
    _ = try store.respond(
        promptID: first.id,
        action: .ignore,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .ignore),
        surface: .dashboard
    )
    let replay = try store.enqueue(promptDraft(decisionKey: "drift:same")).episode

    let reopened = try PromptInboxStore(databaseURL: url, now: { clock.now })
    let restored = try reopened.timeline()
    #expect(restored.awaitingResponse.map(\.episode.id) == [replay.id])
    #expect(restored.awaitingResponse.first?.occurrence == 2)
    #expect(restored.awaitingResponse.first?.isReplay == true)
    #expect(restored.snoozed.map(\.episode.id) == [snoozed.id])
    #expect(restored.snoozed.first?.availableAt == snoozeUntil)
    #expect(restored.recent.map(\.episode.id) == [first.id])
    #expect(restored.recent.first?.response?.action == .ignore)

    clock.advance(by: 301)
    let returned = try reopened.timeline()
    #expect(Set(returned.awaitingResponse.map(\.episode.id)) == Set([replay.id, snoozed.id]))
    #expect(returned.snoozed.isEmpty)

    _ = try reopened.dismiss(promptID: replay.id)
    let dismissed = try reopened.timeline()
    #expect(dismissed.recent.first?.episode.id == replay.id)
    #expect(dismissed.recent.first?.episode.state == .dismissed)
}

@Test
func promptInboxTimelineExpiresDueEpisodesAndRejectsInvalidHistoryLimits() throws {
    let url = temporaryPromptInboxURL("timeline-expiry")
    defer { removePromptInboxDatabase(url) }
    let clock = PromptInboxTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = try PromptInboxStore(databaseURL: url, now: { clock.now })
    let episode = try store.enqueue(promptDraft(
        decisionKey: "expiring",
        expiresAt: clock.now.addingTimeInterval(30)
    )).episode

    clock.advance(by: 31)
    let timeline = try store.timeline(recentLimit: 1)
    #expect(timeline.awaitingResponse.isEmpty)
    #expect(timeline.recent.map(\.episode.id) == [episode.id])
    #expect(timeline.recent.first?.episode.state == .timedOut)
    #expect(throws: PromptInboxStoreError.invalidLimit) {
        try store.timeline(recentLimit: -1)
    }
}

@Test
func promptInboxRefusesToDismissAMandatoryDecision() throws {
    let url = temporaryPromptInboxURL("mandatory-dismissal")
    defer { removePromptInboxDatabase(url) }
    let store = try PromptInboxStore(databaseURL: url)
    let mandatory = try store.enqueue(PromptDraft(
        decisionKey: "onboarding:mandatory",
        type: "ONBOARDING_TEST",
        title: "Continue setup",
        summary: "Choose how to continue.",
        actions: [PromptAction(kind: .continueIntentionally, title: "Continue")]
    )).episode

    #expect(mandatory.allowsDismissal == false)
    #expect(throws: PromptInboxStoreError.dismissalNotAllowed) {
        try store.dismiss(promptID: mandatory.id)
    }
    #expect(try store.episode(promptID: mandatory.id)?.state == .queued)
}

private func promptDraft(decisionKey: String, expiresAt: Date? = nil) -> PromptDraft {
    PromptDraft(
        decisionKey: decisionKey,
        type: "meeting_candidate",
        title: "Meeting detected",
        summary: "Add the detected meeting?",
        actions: [
            PromptAction(kind: .addMeeting, title: "Add", role: .primary),
            PromptAction(kind: .editMeeting, title: "Edit"),
            PromptAction(kind: .ignore, title: "Ignore")
        ],
        payload: ["candidateID": "candidate-1", "allowsDismissal": "true"],
        expiresAt: expiresAt
    )
}

@Test
func promptInboxRejectsMoreThanThreeSecondaryActionsOnEverySurface() throws {
    let url = temporaryPromptInboxURL("too-many-secondary-actions")
    defer { removePromptInboxDatabase(url) }
    let store = try PromptInboxStore(databaseURL: url)
    let actions = [
        PromptAction(kind: .returnToActiveTask, title: "Return", role: .primary),
        PromptAction(kind: .startShortSprint, title: "Short sprint"),
        PromptAction(kind: .fiveMoreMinutes, title: "Five more minutes"),
        PromptAction(kind: .startBreak, title: "Take a break"),
        PromptAction(kind: .continueIntentionally, title: "Continue intentionally")
    ]
    let draft = PromptDraft(
        decisionKey: "too-many-actions",
        type: "GAMING_DRIFT",
        title: "Choose a next step",
        summary: "The current session contains 10 observed minutes in Steam. This shows activity, not why it happened or what you intended.",
        actions: actions,
        payload: [
            "behaviorPromptContractVersion": BehaviorPromptPresentationPolicy.contractVersion,
            "observedGamingMinutes": "10",
            "evidenceStartedAtEpoch": "1000",
            "evidenceLatestAtEpoch": "1540"
        ]
    )

    #expect(BehaviorPromptPresentationPolicy.issues(for: draft) == [.tooManySecondaryActions])
    #expect(throws: PromptInboxStoreError.invalidDraft) {
        try store.enqueue(draft)
    }
    #expect(try store.unresolved().isEmpty)
}

@Test
func behaviorPromptContractRejectsUnreliableCoerciveOrIntentAssertingCopy() throws {
    let url = temporaryPromptInboxURL("behavior-prompt-contract")
    defer { removePromptInboxDatabase(url) }
    let store = try PromptInboxStore(databaseURL: url)
    let basePayload = [
        "behaviorPromptContractVersion": BehaviorPromptPresentationPolicy.contractVersion,
        "observedGamingMinutes": "10",
        "evidenceStartedAtEpoch": "1000",
        "evidenceLatestAtEpoch": "1540"
    ]
    let action = PromptAction(kind: .returnToActiveTask, title: "Return", role: .primary)

    let coercive = PromptDraft(
        decisionKey: "coercive",
        type: "GAMING_DRIFT",
        title: "You failed",
        summary: "The current session contains 10 observed minutes. This shows activity, not why it happened or what you intended.",
        actions: [action],
        payload: basePayload
    )
    #expect(BehaviorPromptPresentationPolicy.issues(for: coercive).contains(.coerciveLanguage))
    #expect(throws: PromptInboxStoreError.invalidDraft) { try store.enqueue(coercive) }

    let assertedIntent = PromptDraft(
        decisionKey: "asserted-intent",
        type: "GAMING_DRIFT",
        title: "Return?",
        summary: "You are avoiding the task after 10 observed minutes.",
        actions: [action],
        payload: basePayload
    )
    let intentIssues = BehaviorPromptPresentationPolicy.issues(for: assertedIntent)
    #expect(intentIssues.contains(.assertedIntent))
    #expect(intentIssues.contains(.missingUncertaintyBoundary))
    #expect(throws: PromptInboxStoreError.invalidDraft) { try store.enqueue(assertedIntent) }

    let unreliable = PromptDraft(
        decisionKey: "unreliable-time",
        type: "GAMING_DRIFT",
        title: "Return?",
        summary: "The current session contains 12 observed minutes. This shows activity, not why it happened or what you intended.",
        actions: [action],
        payload: basePayload
    )
    #expect(BehaviorPromptPresentationPolicy.issues(for: unreliable).contains(.unreliableElapsedEvidence))
    #expect(throws: PromptInboxStoreError.invalidDraft) { try store.enqueue(unreliable) }
    #expect(try store.unresolved().isEmpty)
}

private final class PromptInboxTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ date: Date) { stored = date }

    var now: Date { lock.withLock { stored } }

    func advance(by interval: TimeInterval) {
        lock.withLock { stored = stored.addingTimeInterval(interval) }
    }
}

private final class PromptInboxIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String {
        lock.withLock { values.removeFirst() }
    }
}

private func temporaryPromptInboxURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("zoid-prompt-inbox-\(label)-\(UUID().uuidString).sqlite")
}

private func removePromptInboxDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
}
