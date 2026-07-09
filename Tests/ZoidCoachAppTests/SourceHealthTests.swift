import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func initialSourcesRepresentAllRequiredIntegrations() {
    let sourceIDs = Set(SourceHealth.initial.map(\.id))

    #expect(sourceIDs == Set([.reminders, .screenwatch, .atoll]))
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
    try? await Task.sleep(for: .milliseconds(500))

    #expect(model.sources.allSatisfy { $0.state != .checking })
    #expect(model.isCheckingSources == false)
}
