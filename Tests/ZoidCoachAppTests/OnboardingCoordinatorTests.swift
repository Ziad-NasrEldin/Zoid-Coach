import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@MainActor
@Test
func freshOnboardingPersistsEachStepAndResumesAfterRestart() throws {
    let store = RecordingOnboardingStore()
    let first = OnboardingCoordinator(store: store, now: { Date(timeIntervalSince1970: 100) })

    #expect(first.route == .onboarding)
    #expect(first.progress.currentStep == .welcome)
    try first.continueFromCurrentStep()
    #expect(first.progress.currentStep == .localPrivacy)
    #expect(store.saved?.persistenceRevision == 1)

    first.exitToToday()
    #expect(first.route == .today)

    let restarted = OnboardingCoordinator(store: store, now: { Date(timeIntervalSince1970: 200) })
    #expect(restarted.route == .onboarding)
    #expect(restarted.progress.currentStep == .localPrivacy)
    #expect(restarted.progress.completedSteps == [.welcome])
}

@MainActor
@Test
func deniedAndDeferredSourcesRemainExplicitAndDoNotBlockSetup() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersDenied },
        requestReminders: { SelfHealth.remindersDenied },
        inspectScreenwatch: { SelfHealth.screenwatchMissing },
        inspectNotifications: { SelfHealth.notificationsDenied },
        requestNotifications: { SelfHealth.notificationsDenied },
        loadInventory: { .init(items: [], warning: nil) },
        testDelivery: { .init(state: .unavailable, message: "Notifications are disabled") }
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)
    #expect(coordinator.progress.remindersAccess == .denied)
    #expect(coordinator.sourceHealth[.reminders]?.detail == "Reminders access is unavailable")
    try coordinator.continueFromCurrentStep()
    coordinator.deferAccess(for: .screenwatch)
    #expect(coordinator.progress.screenwatchAccess == .deferred)
    #expect(coordinator.canContinue)
}

@MainActor
private final class RecordingOnboardingStore: OnboardingProgressPersisting {
    var saved: OnboardingProgress?

    init(progress: OnboardingProgress? = nil) {
        saved = progress
    }

    func load() throws -> OnboardingProgress {
        if let saved { return saved }
        return try OnboardingProgress()
    }

    func save(_ progress: OnboardingProgress) throws -> OnboardingProgress {
        let replacement = try progress.withPersistenceRevisionForAppTests(
            (saved?.persistenceRevision ?? 0) + 1
        )
        saved = replacement
        return replacement
    }
}

@MainActor
private enum SelfHealth {
    static let remindersDenied = SourceHealth(
        id: .reminders,
        title: "Apple Reminders",
        eyebrow: "Intent",
        state: .attention,
        detail: "Reminders access is unavailable",
        evidence: "Continue with manual local planning",
        actionTitle: "Repair"
    )
    static let screenwatchMissing = SourceHealth(
        id: .screenwatch,
        title: "Screenwatch",
        eyebrow: "Behavior",
        state: .unavailable,
        detail: "Today’s telemetry stream is missing",
        evidence: "No captured content was displayed",
        actionTitle: "Retry"
    )
    static let notificationsDenied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Delivery",
        state: .attention,
        detail: "Notifications are unavailable",
        evidence: "Use Today for coaching choices",
        actionTitle: "Repair"
    )
}

private func progressAt(_ target: OnboardingStep) throws -> OnboardingProgress {
    var progress = try OnboardingProgress()
    while progress.currentStep != target {
        if [.reminders, .screenwatch, .notifications].contains(progress.currentStep) {
            try progress.recordAccessDecision(.deferred, for: progress.currentStep)
        }
        if progress.currentStep == .coachingMode {
            progress.chooseCoachingMode(.rulesOnly)
        }
        try progress.completeCurrentStep(at: Date(timeIntervalSince1970: 1))
    }
    return progress
}

private extension OnboardingProgress {
    func withPersistenceRevisionForAppTests(_ revision: UInt64) throws -> Self {
        try Self(
            persistenceRevision: revision,
            currentStep: currentStep,
            completedSteps: completedSteps,
            coachingMode: coachingMode,
            remindersAccess: remindersAccess,
            screenwatchAccess: screenwatchAccess,
            notificationAccess: notificationAccess,
            finishedAt: finishedAt
        )
    }
}
