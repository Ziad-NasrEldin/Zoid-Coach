import AppKit
import Foundation
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

enum OnboardingDependencyError: LocalizedError {
    case gamingPolicyPersistenceUnavailable

    var errorDescription: String? {
        "Gaming policy storage is not available yet. Your choice was not marked complete."
    }
}

@MainActor
struct OnboardingDependencies {
    let inspectReminders: () async -> SourceHealth
    let requestReminders: () async -> SourceHealth
    let inspectScreenwatch: () async -> SourceHealth
    let inspectScreenwatchSetup: () async -> ScreenwatchSetupStatus
    let selectScreenwatchDirectory: (URL) async throws -> ScreenwatchSetupStatus
    let useDefaultScreenwatchDirectory: () async -> ScreenwatchSetupStatus
    let inspectNotifications: () async -> SourceHealth
    let requestNotifications: () async -> SourceHealth
    let loadInventory: () -> AppInventoryLoadResult
    let testDelivery: () async -> OnboardingDeliveryResult
    let loadPolicy: () throws -> UserPolicy
    let savePolicy: (UserPolicy) throws -> Void
    let loadGamingPolicy: () throws -> GamingPolicy
    let saveGamingPolicy: (GamingPolicy) throws -> Void
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
        let policyStore = try? PolicyStore(databaseURL: runtimeEnvironment.databaseURL)
        return Self(
            inspectReminders: { await reminders.inspect() },
            requestReminders: { await reminders.requestAccessAndInspect() },
            inspectScreenwatch: { await screenwatch.inspect() },
            inspectScreenwatchSetup: { await screenwatchSetup.inspect() },
            selectScreenwatchDirectory: { try await screenwatchSetup.selectAlternateDaysDirectory($0) },
            useDefaultScreenwatchDirectory: { await screenwatchSetup.useDefaultLocation() },
            inspectNotifications: { await notifications.inspect() },
            requestNotifications: { await notifications.requestAccessAndInspect() },
            loadInventory: { inventory.load() },
            testDelivery: { await delivery.run() },
            loadPolicy: {
                guard let policyStore else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try policyStore.current()?.policy ?? UserPolicy.defaults()
            },
            savePolicy: { policy in
                guard let policyStore else {
                    throw CocoaError(.fileNoSuchFile)
                }
                _ = try policyStore.save(policy)
            },
            loadGamingPolicy: {
                throw OnboardingDependencyError.gamingPolicyPersistenceUnavailable
            },
            saveGamingPolicy: { _ in
                throw OnboardingDependencyError.gamingPolicyPersistenceUnavailable
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
}
