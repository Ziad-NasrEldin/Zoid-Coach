import AtollExtensionKit
import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func atollDescriptorUsesOnlyTheLocalCapabilityEndpoint() {
    let episode = atollTestEpisode()
    let builder = AtollPromptDescriptorBuilder(bundleIdentifier: "test.zoid")

    let descriptor = builder.descriptor(for: episode, loopbackPort: 43123)
    let web = descriptor.tab?.webContent
    let addToken = PromptResponseToken.make(promptID: episode.id, action: .addMeeting)

    #expect(descriptor.metadata["promptID"] == episode.id)
    #expect(descriptor.tab?.allowWebInteraction == true)
    #expect(web?.allowLocalhostRequests == true)
    #expect(web?.allowRemoteRequests == false)
    #expect(web?.html.contains("http://127.0.0.1:43123/") == true)
    #expect(web?.html.contains(addToken) == true)
    #expect(web?.html.contains("https://") == false)
    #expect(web?.html.contains("&lt;/script&gt;") == true)
}

@Test
func atollLoopbackAppliesOnePersistedResponseAcrossRepeatedClicks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-atoll-prompt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
    let archive = try ScreenwatchArchive(databaseURL: databaseURL)
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let handler = AtollPromptActionHandler(
        promptStore: promptStore,
        effectRouter: PromptResponseEffectRouter(outbox: outbox, meetingArchive: archive)
    )
    let server = AtollPromptLoopbackServer(handler: handler)
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "plan:2026-07-10",
        type: "PLAN_READY",
        title: "Plan ready",
        summary: "Review today's commitments",
        actions: [PromptAction(kind: .acceptPlan, title: "Accept", role: .primary)]
    )).episode
    let port = try await server.start()
    let token = PromptResponseToken.make(promptID: episode.id, action: .acceptPlan)
    let url = AtollPromptDescriptorBuilder().endpointURL(
        promptID: episode.id,
        action: .acceptPlan,
        actionToken: token,
        loopbackPort: port
    )

    let first = try await post(to: url)
    let repeated = try await post(to: url)

    #expect(first == 200)
    #expect(repeated == 200)
    #expect(try promptStore.responses(promptID: episode.id).count == 1)
    #expect(try promptStore.episode(promptID: episode.id)?.state == .responded)
    server.stop()
}

@Test
func atollLoopbackRejectsAnActionTokenForAnotherAction() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-atoll-token-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
    let handler = AtollPromptActionHandler(
        promptStore: promptStore,
        effectRouter: PromptResponseEffectRouter(
            outbox: try ActionOutboxStore(databaseURL: databaseURL),
            meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL)
        )
    )
    let server = AtollPromptLoopbackServer(handler: handler)
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "plan:token-test",
        type: "PLAN_READY",
        title: "Plan ready",
        summary: "Review",
        actions: [PromptAction(kind: .acceptPlan, title: "Accept")]
    )).episode
    let port = try await server.start()
    let wrongToken = PromptResponseToken.make(promptID: episode.id, action: .ignore)
    let url = AtollPromptDescriptorBuilder().endpointURL(
        promptID: episode.id,
        action: .acceptPlan,
        actionToken: wrongToken,
        loopbackPort: port
    )

    #expect(try await post(to: url) == 409)
    #expect(try promptStore.responses(promptID: episode.id).isEmpty)
    server.stop()
}

private func atollTestEpisode() -> PromptEpisode {
    PromptEpisode(
        id: "prompt-1",
        decisionKey: "meeting:abc",
        type: "MEETING_CANDIDATE",
        state: .queued,
        title: "Meeting </script>",
        summary: "Add the detected meeting?",
        actions: [
            PromptAction(kind: .addMeeting, title: "Add", role: .primary),
            PromptAction(kind: .ignore, title: "Ignore")
        ],
        payload: ["candidateID": "abc"],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func post(to url: URL) async throws -> Int {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let (_, response) = try await URLSession.shared.data(for: request)
    return try #require((response as? HTTPURLResponse)?.statusCode)
}
