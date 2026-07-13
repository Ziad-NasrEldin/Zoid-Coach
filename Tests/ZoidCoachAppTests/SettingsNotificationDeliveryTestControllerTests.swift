import Foundation
import Testing
@testable import ZoidCoachApp

@MainActor
@Test
func settingsNotificationTestShowsExactOutcomeAndSupportsRetry() async {
    let recorder = NotificationDeliveryTestRecorder(results: [
        OnboardingDeliveryResult(state: .scheduled, message: "macOS accepted the test."),
        OnboardingDeliveryResult(state: .failed, message: "Delivery failed. Use Today.")
    ])
    let controller = SettingsNotificationDeliveryTestController {
        await recorder.next()
    }

    #expect(controller.buttonTitle == "SEND TEST NOTIFICATION")
    controller.sendTest()
    await waitForNotificationResult(controller)
    #expect(controller.result == OnboardingDeliveryResult(state: .scheduled, message: "macOS accepted the test."))
    #expect(controller.buttonTitle == "SEND ANOTHER TEST")

    controller.sendTest()
    await waitForNotificationResult(controller, expectedMessage: "Delivery failed. Use Today.")
    #expect(controller.result == OnboardingDeliveryResult(state: .failed, message: "Delivery failed. Use Today."))
    #expect(await recorder.callCount() == 2)
}

@MainActor
@Test
func settingsNotificationTestSuppressesDuplicateClicksWhileRunning() async {
    let gate = NotificationDeliveryTestGate()
    let controller = SettingsNotificationDeliveryTestController {
        await gate.run()
    }

    controller.sendTest()
    controller.sendTest()
    while await gate.callCount() == 0 { await Task.yield() }

    #expect(controller.isRunning)
    #expect(controller.buttonTitle == "SENDING TEST")
    #expect(await gate.callCount() == 1)

    await gate.finish(OnboardingDeliveryResult(
        state: .unavailable,
        message: "Notifications are not enabled. Coaching choices remain available in Today."
    ))
    await waitForNotificationResult(controller)

    #expect(controller.result?.state == .unavailable)
    #expect(controller.result?.message.contains("available in Today") == true)
}

@MainActor
private func waitForNotificationResult(
    _ controller: SettingsNotificationDeliveryTestController,
    expectedMessage: String? = nil
) async {
    for _ in 0..<100 {
        if let result = controller.result,
           expectedMessage == nil || result.message == expectedMessage {
            return
        }
        await Task.yield()
    }
}

private actor NotificationDeliveryTestRecorder {
    private var results: [OnboardingDeliveryResult]
    private var calls = 0

    init(results: [OnboardingDeliveryResult]) {
        self.results = results
    }

    func next() -> OnboardingDeliveryResult {
        calls += 1
        return results.removeFirst()
    }

    func callCount() -> Int { calls }
}

private actor NotificationDeliveryTestGate {
    private var calls = 0
    private var continuation: CheckedContinuation<OnboardingDeliveryResult, Never>?

    func run() async -> OnboardingDeliveryResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func callCount() -> Int { calls }

    func finish(_ result: OnboardingDeliveryResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
