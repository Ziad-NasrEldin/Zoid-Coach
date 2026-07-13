import Combine
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class SettingsNotificationDeliveryTestController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case finished(OnboardingDeliveryResult)
    }

    @Published private(set) var phase: Phase = .idle

    private let runTest: @MainActor @Sendable () async -> OnboardingDeliveryResult

    init(
        runTest: @escaping @MainActor @Sendable () async -> OnboardingDeliveryResult = SettingsNotificationDeliveryTestController.runLiveTest
    ) {
        self.runTest = runTest
    }

    var isRunning: Bool { phase == .running }

    var buttonTitle: String {
        switch phase {
        case .idle: "SEND TEST NOTIFICATION"
        case .running: "SENDING TEST"
        case .finished: "SEND ANOTHER TEST"
        }
    }

    var result: OnboardingDeliveryResult? {
        guard case let .finished(result) = phase else { return nil }
        return result
    }

    func sendTest() {
        guard !isRunning else { return }
        phase = .running
        Task {
            phase = .finished(await runTest())
        }
    }

    private static func runLiveTest() async -> OnboardingDeliveryResult {
        let runtimeEnvironment = RuntimeEnvironment.current()
        let fixtureAdapter: DeterministicOSFixtureAdapters?
        if case .qa = runtimeEnvironment.mode {
            fixtureAdapter = try? QAFixtureOSComposition.makeAuthorizedAdapter(
                runtimeEnvironment: runtimeEnvironment
            )
        } else {
            fixtureAdapter = nil
        }
        return await OnboardingDeliveryTestService(
            runtimeEnvironment: runtimeEnvironment,
            fixtureAdapter: fixtureAdapter
        ).run()
    }
}
