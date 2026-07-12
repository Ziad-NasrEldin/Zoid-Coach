import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct OnboardingDeliveryResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case delivered
        case unavailable
        case failed
    }

    let state: State
    let message: String
}

@MainActor
struct OnboardingDependencies {
    let inspectReminders: () async -> SourceHealth
    let requestReminders: () async -> SourceHealth
    let inspectScreenwatch: () async -> SourceHealth
    let inspectNotifications: () async -> SourceHealth
    let requestNotifications: () async -> SourceHealth
    let loadInventory: () -> AppInventoryLoadResult
    let testDelivery: () async -> OnboardingDeliveryResult

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
        let inventory = AppInventoryService(databaseURL: runtimeEnvironment.databaseURL)
        let delivery = OnboardingDeliveryTestService(
            runtimeEnvironment: runtimeEnvironment,
            fixtureAdapter: fixtureAdapter
        )
        return Self(
            inspectReminders: { await reminders.inspect() },
            requestReminders: { await reminders.requestAccessAndInspect() },
            inspectScreenwatch: { await screenwatch.inspect() },
            inspectNotifications: { await notifications.inspect() },
            requestNotifications: { await notifications.requestAccessAndInspect() },
            loadInventory: { inventory.load() },
            testDelivery: { await delivery.run() }
        )
    }
}
