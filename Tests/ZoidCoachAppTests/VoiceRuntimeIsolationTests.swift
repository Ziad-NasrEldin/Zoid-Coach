import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@MainActor
@Test
func qaVoiceFailsClosedWithoutProductionDashboardConnection() async throws {
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-voice-qa-\(UUID().uuidString)"],
        processEnvironment: [:]
    ).environment
    let model = VoiceConversationModel(runtimeEnvironment: runtimeEnvironment)

    #expect(!model.isDashboardConnectionEnabled)
    model.toggleSession(source: .text)
    try await Task.sleep(for: .milliseconds(50))

    #expect(model.state == .disconnected)
    #expect(model.statusMessage == "QA voice agent is disabled until it has a dedicated service identity")
}
