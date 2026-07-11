import Foundation
import Testing
@testable import ZoidCoachApp

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
