import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func initialSourcesRepresentAllRequiredIntegrations() {
    let sourceIDs = Set(SourceHealth.initial.map(\.id))

    #expect(sourceIDs == Set([.reminders, .calendar, .screenwatch, .agent, .notifications]))
}

@Test
func healthStatesAlwaysExposeWrittenLabels() {
    for state in [HealthState.healthy, .checking, .attention, .notConnected, .unavailable] {
        #expect(!state.rawValue.isEmpty)
    }
}

@MainActor
@Test
func sourceCheckCompletesWithStableSourceStates() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = AppModel(screenwatchReader: ScreenwatchReader(baseDirectory: root))

    model.runSourceCheck()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(15))
    while model.isCheckingSources, clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
    }

    #expect(model.sources.allSatisfy { $0.state != .checking })
    #expect(model.isCheckingSources == false)
}

@MainActor
@Test
func appModelPropagatesQARuntimeToBackgroundAgentControl() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-app-model-qa-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let model = AppModel(
        runtimeEnvironment: runtimeEnvironment,
        screenwatchReader: ScreenwatchReader(baseDirectory: runtimeEnvironment.screenwatchDirectory)
    )
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))

    while model.sources.first(where: { $0.id == .agent })?.detail
        != "QA background agent is disabled",
        clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(
        model.sources.first(where: { $0.id == .agent })?.detail
            == "QA background agent is disabled"
    )
}
