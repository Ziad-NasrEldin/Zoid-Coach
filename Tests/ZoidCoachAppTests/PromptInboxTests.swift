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
    #expect(throws: PromptStateMachineError.invalidTransition(from: .responded, event: .present)) {
        try stateMachine.transition(from: .responded, on: .present)
    }
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

    let applied = try store.respond(promptID: first.id, action: .addMeeting, actionToken: token, surface: .atoll)
    let replay = try store.respond(promptID: first.id, action: .addMeeting, actionToken: token, surface: .notification)
    let next = try store.enqueue(promptDraft(decisionKey: "meeting:abc"))

    #expect(applied.wasApplied)
    #expect(applied.episode.state == .responded)
    #expect(replay.wasApplied == false)
    #expect(replay.response == applied.response)
    #expect(try store.responses(promptID: first.id).count == 1)
    #expect(next.wasInserted)
    #expect(next.episode.id == "prompt-2")
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
        payload: ["candidateID": "candidate-1"],
        expiresAt: expiresAt
    )
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
