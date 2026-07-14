import Combine
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class SettingsNotificationDeliveryTestController: ObservableObject {
    static let liveQAMarkerRelativePath = "QA Control/live-system-notification-test.enabled"

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
        let useLiveSystemCenter = shouldUseLiveSystemCenter(
            runtimeEnvironment: runtimeEnvironment
        )
        let fixtureAdapter: DeterministicOSFixtureAdapters?
        if case .qa = runtimeEnvironment.mode, !useLiveSystemCenter {
            fixtureAdapter = try? QAFixtureOSComposition.makeAuthorizedAdapter(
                runtimeEnvironment: runtimeEnvironment
            )
        } else {
            fixtureAdapter = nil
        }
        return await OnboardingDeliveryTestService(
            runtimeEnvironment: runtimeEnvironment,
            fixtureAdapter: fixtureAdapter,
            useLiveSystemCenterInPackagedQA: useLiveSystemCenter
        ).run()
    }

    static func shouldUseLiveSystemCenter(
        runtimeEnvironment: RuntimeEnvironment,
        fileManager: FileManager = .default
    ) -> Bool {
        guard case let .qa(runRoot) = runtimeEnvironment.mode,
              runtimeEnvironment.packageMode == .qa,
              runtimeEnvironment.identity == .qa else {
            return false
        }
        let marker = runRoot.appendingPathComponent(liveQAMarkerRelativePath)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: marker.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
