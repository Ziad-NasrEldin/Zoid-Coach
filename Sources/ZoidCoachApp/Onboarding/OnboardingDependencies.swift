import AppKit
import EventKit
import Foundation
import UserNotifications
import ZoidCoachCore
import ZoidCoachInfrastructure

struct OnboardingDeliveryResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case delivered
        case scheduled
        case unavailable
        case failed
    }

    let state: State
    let message: String
}

struct OnboardingAccessRequestResult: Equatable, Sendable {
    let health: SourceHealth
    let decision: OnboardingAccessDecision
}

struct OnboardingFirstPlanItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let estimateMinutes: Int?
    let isMainObjective: Bool
}

struct OnboardingFirstDailyPlanResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case prepared
        case unavailable
        case failed
    }

    let state: State
    let items: [OnboardingFirstPlanItem]
    let message: String
}

enum OnboardingDependencyError: LocalizedError {
    case gamingPolicyPersistenceUnavailable
    case firstDailyPlanUnavailable
    case invalidPolicyMutationReceipt

    var errorDescription: String? {
        switch self {
        case .gamingPolicyPersistenceUnavailable:
            "Gaming policy storage is not available yet. Your choice was not marked complete."
        case .firstDailyPlanUnavailable:
            "A visible first daily plan has not been prepared. Setup was not marked complete."
        case .invalidPolicyMutationReceipt:
            "The agent did not return a durable policy receipt. Setup was not advanced."
        }
    }
}

@MainActor
struct OnboardingDependencies {
    let inspectReminders: () async -> SourceHealth
    let requestReminders: () async -> OnboardingAccessRequestResult
    let inspectScreenwatch: () async -> SourceHealth
    let inspectScreenwatchSetup: () async -> ScreenwatchSetupStatus
    let selectScreenwatchDirectory: (URL) async throws -> ScreenwatchSetupStatus
    let useDefaultScreenwatchDirectory: () async -> ScreenwatchSetupStatus
    let inspectNotifications: () async -> SourceHealth
    let requestNotifications: () async -> OnboardingAccessRequestResult
    let loadInventory: () -> AppInventoryLoadResult
    let testDelivery: () async -> OnboardingDeliveryResult
    let loadPolicy: () throws -> VersionedUserPolicy?
    let applyPolicyMutation: (PolicyMutationRequest) async throws -> PolicyMutationReceipt
    let prepareFirstDailyPlan: () async -> OnboardingFirstDailyPlanResult
    let openSystemSettings: (OnboardingStep) -> Bool

    static func live(runtimeEnvironment: RuntimeEnvironment) -> Self {
        let reminders: any RemindersServicing
        let notifications: any NotificationServicing
        let fixtureAdapter: DeterministicOSFixtureAdapters?
        if case .qa = runtimeEnvironment.mode {
            fixtureAdapter = try? QAFixtureOSComposition.makeAuthorizedAdapter(
                runtimeEnvironment: runtimeEnvironment
            )
            if let fixtureAdapter {
                reminders = QAFixtureRemindersService(adapter: fixtureAdapter)
                notifications = QAFixtureNotificationService(adapter: fixtureAdapter)
            } else {
                reminders = DisabledQARemindersService(
                    detail: "The signed QA fixture could not be loaded"
                )
                notifications = DisabledQANotificationService(
                    detail: "The signed QA fixture could not be loaded"
                )
            }
        } else {
            fixtureAdapter = nil
            reminders = RemindersService()
            notifications = NotificationService(runtimeEnvironment: runtimeEnvironment)
        }
        let screenwatch = ScreenwatchReader(
            baseDirectory: runtimeEnvironment.screenwatchDirectory
        )
        let screenwatchSetup = ScreenwatchSetupService(runtimeEnvironment: runtimeEnvironment)
        let inventory = AppInventoryService(databaseURL: runtimeEnvironment.databaseURL)
        let delivery = OnboardingDeliveryTestService(
            runtimeEnvironment: runtimeEnvironment,
            fixtureAdapter: fixtureAdapter
        )
        let policyStore = try? PolicyStore(
            databaseURL: runtimeEnvironment.databaseURL,
            readOnly: true
        )
        let xpcClient = TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)
        let firstDailyPlanService = try? OnboardingFirstDailyPlanService(
            databaseURL: runtimeEnvironment.databaseURL,
            remindersService: reminders
        )
        return Self(
            inspectReminders: { await reminders.inspect() },
            requestReminders: {
                let health = await reminders.requestAccessAndInspect()
                let decision: OnboardingAccessDecision
                if let fixtureAdapter {
                    decision = Self.decision(from: try? fixtureAdapter.permission(.reminders))
                } else {
                    decision = Self.remindersDecisionFromSystem()
                }
                return .init(health: health, decision: decision)
            },
            inspectScreenwatch: { await screenwatch.inspect() },
            inspectScreenwatchSetup: { await screenwatchSetup.inspect() },
            selectScreenwatchDirectory: { try await screenwatchSetup.selectAlternateDaysDirectory($0) },
            useDefaultScreenwatchDirectory: { await screenwatchSetup.useDefaultLocation() },
            inspectNotifications: { await notifications.inspect() },
            requestNotifications: {
                let health = await notifications.requestAccessAndInspect()
                let decision: OnboardingAccessDecision
                if let fixtureAdapter {
                    decision = Self.decision(from: try? fixtureAdapter.permission(.notifications))
                } else {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    decision = Self.decision(from: settings.authorizationStatus)
                }
                return .init(health: health, decision: decision)
            },
            loadInventory: { inventory.load() },
            testDelivery: { await delivery.run() },
            loadPolicy: {
                guard let policyStore else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try policyStore.current()
            },
            applyPolicyMutation: { request in
                let agentReceipt = try await xpcClient.savePolicyMutation(request)
                guard let receipt = agentReceipt.policyMutationReceipt else {
                    throw OnboardingDependencyError.invalidPolicyMutationReceipt
                }
                return receipt
            },
            prepareFirstDailyPlan: {
                guard let firstDailyPlanService else {
                    return .init(
                        state: .failed,
                        items: [],
                        message: "First-plan storage is unavailable. Setup was not advanced."
                    )
                }
                return await firstDailyPlanService.prepare()
            },
            openSystemSettings: { step in
                let address: String
                switch step {
                case .reminders:
                    address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                case .notifications:
                    address = "x-apple.systempreferences:com.apple.preference.notifications"
                default:
                    return false
                }
                guard let url = URL(string: address) else { return false }
                return NSWorkspace.shared.open(url)
            }
        )
    }

    private static func remindersDecisionFromSystem() -> OnboardingAccessDecision {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: .granted
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .deferred
        @unknown default: .unavailable
        }
    }

    private static func decision(
        from status: UNAuthorizationStatus
    ) -> OnboardingAccessDecision {
        switch status {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .deferred
        @unknown default: .unavailable
        }
    }

    private static func decision(
        from permission: QAFixturePermissionState?
    ) -> OnboardingAccessDecision {
        switch permission {
        case .granted: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .deferred
        case nil: .unavailable
        }
    }
}
