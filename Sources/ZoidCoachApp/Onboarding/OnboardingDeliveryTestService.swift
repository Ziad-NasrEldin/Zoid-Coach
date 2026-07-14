import Foundation
import UserNotifications
import ZoidCoachCore
import ZoidCoachInfrastructure

struct NotificationDeliveryTestSystemClient {
    enum Authorization: Equatable {
        case authorized
        case provisional
        case unavailable
    }

    let authorization: () async -> Authorization
    let schedule: (_ identifier: String, _ title: String, _ body: String) async throws -> Void

    static var live: Self {
        Self(
            authorization: {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                switch settings.authorizationStatus {
                case .authorized: .authorized
                case .provisional: .provisional
                default: .unavailable
                }
            },
            schedule: { identifier, title, body in
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                ))
            }
        )
    }
}

@MainActor
struct OnboardingDeliveryTestService {
    private static let promptID = "settings-notification-delivery-test"
    private static let notificationTitle = "Zoid 666 is ready"
    private static let notificationBody = "This is the delivery check. No action is required."
    private static let repairRoute = "System Settings > Notifications > Zoid 666 > Allow Notifications"

    private let runtimeEnvironment: RuntimeEnvironment
    private let fixtureAdapter: DeterministicOSFixtureAdapters?
    private let useLiveSystemCenterInPackagedQA: Bool
    private let systemClient: NotificationDeliveryTestSystemClient
    private let ledger: NotificationDeliveryLedger?

    init(
        runtimeEnvironment: RuntimeEnvironment,
        fixtureAdapter: DeterministicOSFixtureAdapters?,
        useLiveSystemCenterInPackagedQA: Bool = false,
        systemClient: NotificationDeliveryTestSystemClient = .live,
        ledger: NotificationDeliveryLedger? = nil
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.fixtureAdapter = fixtureAdapter
        self.useLiveSystemCenterInPackagedQA = useLiveSystemCenterInPackagedQA
        self.systemClient = systemClient
        self.ledger = ledger ?? (try? NotificationDeliveryLedger(
            databaseURL: runtimeEnvironment.databaseURL
        ))
    }

    func run() async -> OnboardingDeliveryResult {
        let requestIdentifier = runtimeEnvironment.identity.notification.promptRequestPrefix
            + Self.promptID
        if let fixtureAdapter {
            do {
                guard try fixtureAdapter.permission(.notifications) == .granted else {
                    record(
                        requestIdentifier: requestIdentifier,
                        outcome: .authorizationUnavailable
                    )
                    return .init(
                        state: .unavailable,
                        message: "QA notification permission is not granted. Continue with prompts in Today."
                    )
                }
                _ = try await fixtureAdapter.schedule(.init(
                    category: PromptNotificationCategory.onboardingTest.rawValue,
                    title: Self.notificationTitle,
                    body: Self.notificationBody,
                    promptID: Self.promptID,
                    deliveryDate: Date()
                ))
                let delivered = try fixtureAdapter.deliverDueNotifications()
                record(
                    requestIdentifier: requestIdentifier,
                    outcome: delivered.isEmpty ? .schedulingFailed : .deliveredByFixture,
                    error: delivered.isEmpty ? "fixture_delivery_not_observed" : nil
                )
                return .init(
                    state: delivered.isEmpty ? .failed : .delivered,
                    message: delivered.isEmpty
                        ? "The test could not be delivered. Continue with prompts in Today."
                        : "The QA notification was delivered through the isolated fixture."
                )
            } catch {
                record(
                    requestIdentifier: requestIdentifier,
                    outcome: .schedulingFailed,
                    error: error.localizedDescription
                )
                return .init(
                    state: .failed,
                    message: "The test could not be delivered. Continue with prompts in Today."
                )
            }
        }
        guard canUseSystemCenter else {
            record(
                requestIdentifier: requestIdentifier,
                outcome: .authorizationUnavailable,
                error: "live_notification_boundary_unavailable"
            )
            return .init(
                state: .unavailable,
                message: "The isolated QA notification fixture is unavailable. No production notification API was used."
            )
        }

        guard await systemClient.authorization() != .unavailable else {
            record(
                requestIdentifier: requestIdentifier,
                outcome: .authorizationUnavailable
            )
            return .init(
                state: .unavailable,
                message: "Notifications are not enabled. Open \(Self.repairRoute). Coaching choices remain available in Today."
            )
        }
        do {
            try await systemClient.schedule(
                requestIdentifier,
                Self.notificationTitle,
                Self.notificationBody
            )
            record(
                requestIdentifier: requestIdentifier,
                outcome: .acceptedBySystem,
                scheduledFor: Date().addingTimeInterval(1)
            )
            return .init(
                state: .scheduled,
                message: "macOS accepted the test notification for delivery. Confirm it appears, or use Today for prompts."
            )
        } catch {
            record(
                requestIdentifier: requestIdentifier,
                outcome: .schedulingFailed,
                error: error.localizedDescription
            )
            return .init(
                state: .failed,
                message: "macOS could not schedule the test. Check \(Self.repairRoute), then try again. Prompts remain available in Today."
            )
        }
    }

    private var canUseSystemCenter: Bool {
        switch runtimeEnvironment.mode {
        case .production:
            return true
        case .qa:
            return useLiveSystemCenterInPackagedQA
                && runtimeEnvironment.packageMode == .qa
                && runtimeEnvironment.identity == .qa
        }
    }

    private func record(
        requestIdentifier: String,
        outcome: NotificationDeliveryOutcome,
        scheduledFor: Date? = nil,
        error: String? = nil
    ) {
        try? ledger?.record(
            requestIdentifier: requestIdentifier,
            promptID: Self.promptID,
            category: PromptNotificationCategory.onboardingTest.rawValue,
            outcome: outcome,
            scheduledFor: scheduledFor,
            error: error
        )
        try? ledger?.enforceRetention()
    }
}
