import Foundation
import UserNotifications
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
struct OnboardingDeliveryTestService {
    private let runtimeEnvironment: RuntimeEnvironment
    private let fixtureAdapter: DeterministicOSFixtureAdapters?

    init(
        runtimeEnvironment: RuntimeEnvironment,
        fixtureAdapter: DeterministicOSFixtureAdapters?
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.fixtureAdapter = fixtureAdapter
    }

    func run() async -> OnboardingDeliveryResult {
        if let fixtureAdapter {
            do {
                guard try fixtureAdapter.permission(.notifications) == .granted else {
                    return .init(
                        state: .unavailable,
                        message: "QA notification permission is not granted. Continue with in-app prompts."
                    )
                }
                _ = try await fixtureAdapter.schedule(.init(
                    category: PromptNotificationCategory.planReady.rawValue,
                    title: "Zoid Coach is ready",
                    body: "This is the delivery check. No action is required.",
                    promptID: "onboarding-delivery-test",
                    deliveryDate: Date()
                ))
                let delivered = try fixtureAdapter.deliverDueNotifications()
                return .init(
                    state: delivered.isEmpty ? .failed : .delivered,
                    message: delivered.isEmpty
                        ? "The QA notification was scheduled but not delivered."
                        : "The QA notification was delivered through the isolated fixture."
                )
            } catch {
                return .init(state: .failed, message: error.localizedDescription)
            }
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
            return .init(
                state: .unavailable,
                message: "Notifications are not enabled. Coaching choices remain available in Today."
            )
        }
        let content = UNMutableNotificationContent()
        content.title = "Zoid Coach is ready"
        content.body = "This is the delivery check. No action is required."
        content.sound = .default
        let identifier = runtimeEnvironment.identity.notification.promptRequestPrefix
            + "onboarding-delivery-test"
        do {
            try await center.add(UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            ))
            return .init(
                state: .delivered,
                message: "The test notification was scheduled. You can also find prompts in Today."
            )
        } catch {
            return .init(state: .failed, message: error.localizedDescription)
        }
    }
}
