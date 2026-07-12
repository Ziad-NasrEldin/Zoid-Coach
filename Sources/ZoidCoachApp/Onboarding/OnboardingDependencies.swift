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
        case todayFallback
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
    case reminderListSelectionRequired
    case testPromptUnavailable

    var errorDescription: String? {
        switch self {
        case .gamingPolicyPersistenceUnavailable:
            "Gaming policy storage is not available yet. Your choice was not marked complete."
        case .firstDailyPlanUnavailable:
            "A visible first daily plan has not been prepared. Setup was not marked complete."
        case .invalidPolicyMutationReceipt:
            "The agent did not return a durable policy receipt. Setup was not advanced."
        case .reminderListSelectionRequired:
            "Choose Include or Exclude for every discovered Reminder list before continuing."
        case .testPromptUnavailable:
            "The canonical onboarding prompt service is unavailable."
        }
    }
}

@MainActor
struct OnboardingDependencies {
    let inspectReminders: () async -> SourceHealth
    let requestReminders: () async -> OnboardingAccessRequestResult
    var discoverReminderLists: () async -> ReminderListLoad = {
        .unavailable("Reminder-list discovery is unavailable.")
    }
    let inspectScreenwatch: () async -> SourceHealth
    let inspectScreenwatchSetup: () async -> ScreenwatchSetupStatus
    let selectScreenwatchDirectory: (URL) async throws -> ScreenwatchSetupStatus
    let useDefaultScreenwatchDirectory: () async -> ScreenwatchSetupStatus
    let inspectNotifications: () async -> SourceHealth
    let requestNotifications: () async -> OnboardingAccessRequestResult
    let loadInventory: () -> AppInventoryLoadResult
    let testDelivery: () async -> OnboardingDeliveryResult
    var createTestPrompt: (String) async throws -> OnboardingTestPromptResult = { _ in
        throw OnboardingDependencyError.testPromptUnavailable
    }
    var loadTestPrompt: (String) async throws -> PromptEpisode? = { _ in nil }
    var respondToTestPrompt: (PromptResponseCommand) async throws -> PromptEpisode = { _ in
        throw OnboardingDependencyError.testPromptUnavailable
    }
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
        let xpcClient = TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)
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
            discoverReminderLists: { await reminders.discoverLists() },
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
            createTestPrompt: { try await xpcClient.createOnboardingTestPrompt(flowID: $0) },
            loadTestPrompt: { try await xpcClient.fetchOnboardingTestPrompt(flowID: $0) },
            respondToTestPrompt: { try await xpcClient.respondToPrompt($0) },
            loadPolicy: {
                guard FileManager.default.fileExists(
                    atPath: runtimeEnvironment.databaseURL.path
                ) else { return nil }
                return try PolicyStore(
                    databaseURL: runtimeEnvironment.databaseURL,
                    readOnly: true
                ).current()
            },
            applyPolicyMutation: { request in
                let agentReceipt = try await xpcClient.savePolicyMutation(request)
                guard let receipt = agentReceipt.policyMutationReceipt else {
                    throw OnboardingDependencyError.invalidPolicyMutationReceipt
                }
                return receipt
            },
            prepareFirstDailyPlan: {
                let firstDailyPlanService: OnboardingFirstDailyPlanService
                do {
                    firstDailyPlanService = try OnboardingFirstDailyPlanService(
                        databaseURL: runtimeEnvironment.databaseURL,
                        remindersService: reminders
                    )
                } catch {
                    return .init(
                        state: .failed,
                        items: [],
                        message: "First-plan storage is unavailable. Setup was not advanced. \(error.localizedDescription)"
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
