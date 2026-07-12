import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
@Test
func freshOnboardingPersistsEachStepAndResumesAfterRestart() async throws {
    let store = RecordingOnboardingStore()
    let first = OnboardingCoordinator(store: store, now: { Date(timeIntervalSince1970: 100) })

    #expect(first.route == .onboarding)
    #expect(first.progress.currentStep == .welcome)
    try await first.continueFromCurrentStep()
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
        requestReminders: { .init(health: SelfHealth.remindersDenied, decision: .denied) },
        inspectScreenwatch: { SelfHealth.screenwatchMissing },
        inspectScreenwatchSetup: { SelfScreenwatch.missing },
        selectScreenwatchDirectory: { _ in SelfScreenwatch.healthy },
        useDefaultScreenwatchDirectory: { SelfScreenwatch.missing },
        inspectNotifications: { SelfHealth.notificationsDenied },
        requestNotifications: { .init(health: SelfHealth.notificationsDenied, decision: .denied) },
        loadInventory: { .init(items: [], warning: nil) },
        testDelivery: { .init(state: .unavailable, message: "Notifications are disabled") },
        loadPolicy: { nil },
        applyPolicyMutation: { try successfulPolicyMutation($0) },
        prepareFirstDailyPlan: { preparedFirstPlan },
        openSystemSettings: { _ in true }
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)
    #expect(coordinator.progress.remindersAccess == .denied)
    #expect(coordinator.sourceHealth[.reminders]?.detail == "Reminders access is unavailable")
    try await coordinator.continueFromCurrentStep()
    #expect(!coordinator.progress.completedEffects.map(\.step).contains(.reminders))
    coordinator.deferAccess(for: .screenwatch)
    #expect(coordinator.progress.screenwatchAccess == .deferred)
    #expect(coordinator.canContinue)
}

@MainActor
@Test
func reminderListDiscoveryFailureBlocksGrantedSetupUntilRetrySucceeds() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let recorder = PolicyRecorder()
    let base = testDependencies(policyRecorder: recorder)
    var attempts = 0
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersHealthy },
        requestReminders: { .init(health: SelfHealth.remindersHealthy, decision: .granted) },
        discoverReminderLists: {
            attempts += 1
            return attempts == 1
                ? .unavailable("Injected discovery failure")
                : .available([ReminderListChoice(id: "work", name: "Work")])
        },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)

    #expect(coordinator.reminderListDiscovery == .failed("Injected discovery failure"))
    #expect(!coordinator.canContinue)

    await coordinator.loadReminderLists()
    coordinator.setReminderListDecision(true, listID: "work")

    #expect(coordinator.reminderListDiscovery == .available([
        ReminderListChoice(id: "work", name: "Work")
    ]))
    #expect(coordinator.canContinue)
}

@MainActor
@Test
func emptyReminderListDiscoveryRequiresExplicitLocalFallbackConfirmation() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let base = testDependencies()
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersHealthy },
        requestReminders: { .init(health: SelfHealth.remindersHealthy, decision: .granted) },
        discoverReminderLists: { .available([]) },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)
    #expect(coordinator.reminderListDiscovery == .empty)
    #expect(!coordinator.canContinue)

    coordinator.confirmEmptyReminderListFallback()

    #expect(coordinator.canContinue)
    #expect(store.saved?.emptyReminderListFallbackConfirmed == true)
}

@MainActor
@Test
func staleReminderListDiscoveryCannotOverwriteTheLatestRetry() async throws {
    var progress = try progressAt(.reminders)
    try progress.recordAccessDecision(.granted, for: .reminders)
    let store = RecordingOnboardingStore(progress: progress)
    let gate = ReminderListRequestGate()
    let base = testDependencies()
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersHealthy },
        requestReminders: { .init(health: SelfHealth.remindersHealthy, decision: .granted) },
        discoverReminderLists: { await gate.wait() },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    let first = Task { await coordinator.loadReminderLists() }
    while gate.requestCount < 1 { await Task.yield() }
    let second = Task { await coordinator.loadReminderLists() }
    while gate.requestCount < 2 { await Task.yield() }

    gate.resumeRequest(1, with: .available([
        ReminderListChoice(id: "latest", name: "Latest")
    ]))
    await second.value
    gate.resumeRequest(0, with: .available([
        ReminderListChoice(id: "stale", name: "Stale")
    ]))
    await first.value

    #expect(coordinator.reminderListDiscovery == .available([
        ReminderListChoice(id: "latest", name: "Latest")
    ]))
}

@MainActor
@Test
func grantedRemindersRequireDurableExplicitListChoicesBeforeAdvancing() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let recorder = PolicyRecorder()
    let base = testDependencies(policyRecorder: recorder)
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersHealthy },
        requestReminders: {
            .init(health: SelfHealth.remindersHealthy, decision: .granted)
        },
        discoverReminderLists: {
            .available([
                ReminderListChoice(id: "personal-id", name: "Personal"),
                ReminderListChoice(id: "work-id", name: "Work"),
            ])
        },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)

    #expect(!coordinator.canContinue)
    coordinator.setReminderListDecision(false, listID: "personal-id")
    #expect(!coordinator.canContinue)
    coordinator.setReminderListDecision(true, listID: "work-id")
    #expect(coordinator.canContinue)

    try await coordinator.continueFromCurrentStep()

    #expect(coordinator.progress.currentStep == .screenwatch)
    #expect(coordinator.progress.completedEffects.map(\.step).contains(.reminders))
    #expect(recorder.policy.reminderLists.isConfigured)
    #expect(recorder.policy.reminderLists.decision(for: "personal-id") == false)
    #expect(recorder.policy.reminderLists.decision(for: "work-id") == true)
}

@MainActor
@Test
func grantedRemindersCannotBeDeferredIntoLegacyIncludeAllBehavior() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let base = testDependencies()
    let dependencies = OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersHealthy },
        requestReminders: { .init(health: SelfHealth.remindersHealthy, decision: .granted) },
        discoverReminderLists: {
            .available([ReminderListChoice(id: "work", name: "Work")])
        },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)
    coordinator.deferAccess(for: .reminders)

    #expect(coordinator.progress.remindersAccess == .granted)
    #expect(!coordinator.canContinue)
    #expect(coordinator.errorMessage?.contains("already connected") == true)
}

@MainActor
@Test
func transientAttentionUsesTypedUnavailableDecisionRatherThanDenial() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let base = testDependencies()
    let transient = SourceHealth(
        id: .reminders,
        title: "Apple Reminders",
        eyebrow: "Intent",
        state: .attention,
        detail: "Permission request failed transiently",
        evidence: "No task data was read",
        actionTitle: "Retry"
    )
    let dependencies = OnboardingDependencies(
        inspectReminders: base.inspectReminders,
        requestReminders: { .init(health: transient, decision: .unavailable) },
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    await coordinator.requestAccess(for: .reminders)

    #expect(coordinator.progress.remindersAccess == .unavailable)
    #expect(coordinator.progress.remindersAccess != .denied)
}

@MainActor
@Test
func allTwelveStepsFinishAndRouteToToday() async throws {
    let store = RecordingOnboardingStore()
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies()
    )

    while coordinator.progress.currentStep != .firstDailyPlan {
        switch coordinator.progress.currentStep {
        case .reminders, .screenwatch, .notifications:
            coordinator.deferAccess(for: coordinator.progress.currentStep)
        case .coachingMode:
            coordinator.selectCoachingMode(.rulesOnly)
        case .deliveryTest:
            coordinator.completeTestTask()
        default:
            break
        }
        #expect(coordinator.canContinue)
        try await coordinator.continueFromCurrentStep()
    }
    await coordinator.prepareFirstDailyPlan()
    try await coordinator.continueFromCurrentStep()

    #expect(coordinator.progress.completedSteps == OnboardingProgress.stepSequence)
    #expect(coordinator.progress.isFinished)
    #expect(coordinator.route == .today)
    #expect(store.saved?.finishedAt != nil)
}

@MainActor
@Test
func deliveryStepRequiresTheTestTaskAndAUsablePromptPath() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.deliveryTest))
    let coordinator = OnboardingCoordinator(store: store, dependencies: testDependencies())

    #expect(!coordinator.canContinue)
    coordinator.completeTestTask()
    coordinator.completeTestTask()
    #expect(coordinator.canContinue)
    try await coordinator.continueFromCurrentStep()
    #expect(coordinator.progress.currentStep == .firstDailyPlan)
}

@MainActor
@Test
func failedDeliveryCannotCompleteTheDeliveryStep() async throws {
    let store = RecordingOnboardingStore(
        progress: try progressAt(.deliveryTest, notificationDecision: .granted)
    )
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(
            deliveryResult: .init(state: .failed, message: "Fixture delivery failed")
        )
    )

    coordinator.completeTestTask()
    await coordinator.runDeliveryTest()

    #expect(coordinator.deliveryResult?.state == .failed)
    #expect(!coordinator.canContinue)
}

@MainActor
@Test
func firstPlanMustReturnVisiblePreparedItemsBeforeFinishing() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.firstDailyPlan))
    let unavailable = OnboardingFirstDailyPlanResult(
        state: .unavailable,
        items: [],
        message: "Planner is unavailable"
    )
    let blocked = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(firstPlan: unavailable)
    )
    await blocked.prepareFirstDailyPlan()
    #expect(!blocked.canContinue)
    await #expect(throws: (any Error).self) { try await blocked.continueFromCurrentStep() }
    #expect(!blocked.progress.isFinished)

    let ready = OnboardingCoordinator(store: store, dependencies: testDependencies())
    await ready.prepareFirstDailyPlan()
    #expect(ready.canContinue)
    try await ready.continueFromCurrentStep()
    #expect(ready.progress.isFinished)
    #expect(ready.route == .today)
}

@MainActor
@Test
func classificationAndScheduleAreAppliedBeforeAdvancing() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.activityClassification))
    let policyRecorder = PolicyRecorder()
    let app = AppInventoryItem(
        name: "Terminal",
        normalizedName: "terminal",
        bundleIdentifier: "com.apple.Terminal",
        isInstalled: true,
        lastObservedAt: nil,
        observationCount: 0
    )
    let dependencies = testDependencies(
        inventory: .init(items: [app], warning: nil),
        policyRecorder: policyRecorder
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    coordinator.loadApplicationInventory()
    coordinator.setClassification(.work, for: app.name)
    try await coordinator.continueFromCurrentStep()
    #expect(policyRecorder.policy.behavior.choice(for: app.name) == .work)

    coordinator.workStartHour = 8
    coordinator.workEndHour = 17
    coordinator.quietStartHour = 21
    coordinator.quietEndHour = 6
    try await coordinator.continueFromCurrentStep()
    #expect(policyRecorder.policy.schedule.workWindows.first?.start == LocalTime(hour: 8, minute: 0))
    #expect(policyRecorder.policy.schedule.workWindows.first?.end == LocalTime(hour: 17, minute: 0))
    #expect(policyRecorder.policy.schedule.quietHours == DailyTimeWindow(
        start: LocalTime(hour: 21, minute: 0),
        end: LocalTime(hour: 6, minute: 0)
    ))
}

@MainActor
@Test
func staleSaveRestoresLatestProgressAndOffersRetry() async throws {
    let store = StaleOnceOnboardingStore()
    let coordinator = OnboardingCoordinator(store: store)

    await #expect(throws: (any Error).self) {
        try await coordinator.continueFromCurrentStep()
    }

    #expect(coordinator.progress.currentStep == .localPrivacy)
    #expect(coordinator.errorMessage?.contains("latest saved step was restored") == true)
    #expect(coordinator.route == .onboarding)
}

@MainActor
@Test
func latePermissionResultCannotOverwriteExplicitDeferral() async throws {
    let gate = PermissionRequestGate()
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    var dependencies = testDependencies()
    dependencies = OnboardingDependencies(
        inspectReminders: dependencies.inspectReminders,
        requestReminders: {
            let health = await gate.wait()
            return .init(health: health, decision: .granted)
        },
        inspectScreenwatch: dependencies.inspectScreenwatch,
        inspectScreenwatchSetup: dependencies.inspectScreenwatchSetup,
        selectScreenwatchDirectory: dependencies.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: dependencies.useDefaultScreenwatchDirectory,
        inspectNotifications: dependencies.inspectNotifications,
        requestNotifications: dependencies.requestNotifications,
        loadInventory: dependencies.loadInventory,
        testDelivery: dependencies.testDelivery,
        loadPolicy: dependencies.loadPolicy,
        applyPolicyMutation: dependencies.applyPolicyMutation,
        prepareFirstDailyPlan: dependencies.prepareFirstDailyPlan,
        openSystemSettings: dependencies.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    let request = Task { await coordinator.requestAccess(for: .reminders) }
    while !coordinator.isWorking { await Task.yield() }
    coordinator.deferAccess(for: .reminders)
    gate.resume(with: SourceHealth(
        id: .reminders,
        title: "Apple Reminders",
        eyebrow: "Intent",
        state: .healthy,
        detail: "Connected",
        evidence: "Fixture",
        actionTitle: "Inspect"
    ))
    await request.value

    #expect(coordinator.progress.remindersAccess == .deferred)
}

@MainActor
@Test
func lateInspectionCannotOverwriteANewerExplicitDecision() async throws {
    let gate = PermissionRequestGate()
    let store = RecordingOnboardingStore(progress: try progressAt(.reminders))
    let base = testDependencies()
    let dependencies = OnboardingDependencies(
        inspectReminders: { await gate.wait() },
        requestReminders: base.requestReminders,
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: base.testDelivery,
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    let inspection = Task { await coordinator.inspectCurrentSource() }
    while !coordinator.isWorking { await Task.yield() }
    coordinator.deferAccess(for: .reminders)
    gate.resume(with: SelfHealth.remindersHealthy)
    await inspection.value

    #expect(coordinator.progress.remindersAccess == .deferred)
    #expect(coordinator.sourceHealth[.reminders] == nil)
}

@MainActor
@Test
func inFlightDeliveryBlocksNavigationAndOtherStepMutations() async throws {
    let gate = DeliveryRequestGate()
    let store = RecordingOnboardingStore(
        progress: try progressAt(.deliveryTest, notificationDecision: .granted)
    )
    let base = testDependencies()
    let dependencies = OnboardingDependencies(
        inspectReminders: base.inspectReminders,
        requestReminders: base.requestReminders,
        inspectScreenwatch: base.inspectScreenwatch,
        inspectScreenwatchSetup: base.inspectScreenwatchSetup,
        selectScreenwatchDirectory: base.selectScreenwatchDirectory,
        useDefaultScreenwatchDirectory: base.useDefaultScreenwatchDirectory,
        inspectNotifications: base.inspectNotifications,
        requestNotifications: base.requestNotifications,
        loadInventory: base.loadInventory,
        testDelivery: { await gate.wait() },
        loadPolicy: base.loadPolicy,
        applyPolicyMutation: base.applyPolicyMutation,
        prepareFirstDailyPlan: base.prepareFirstDailyPlan,
        openSystemSettings: base.openSystemSettings
    )
    let coordinator = OnboardingCoordinator(store: store, dependencies: dependencies)

    let delivery = Task { await coordinator.runDeliveryTest() }
    while !coordinator.isWorking { await Task.yield() }
    coordinator.exitToToday()
    coordinator.completeTestTask()
    #expect(coordinator.progress.currentStep == .deliveryTest)
    #expect(coordinator.route == .onboarding)
    #expect(!coordinator.testTaskCompleted)
    gate.resume(with: .init(state: .delivered, message: "Delivered"))
    await delivery.value
    #expect(coordinator.deliveryResult?.state == .delivered)
}

@MainActor
@Test
func alternateScreenwatchFolderCanCompleteTheSourceStep() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.screenwatch))
    let coordinator = OnboardingCoordinator(store: store, dependencies: testDependencies())

    await coordinator.selectScreenwatchDirectory(URL(fileURLWithPath: "/tmp/screenwatch-days"))

    #expect(coordinator.screenwatchSetupStatus?.source == .alternateFolder)
    #expect(coordinator.progress.screenwatchAccess == .granted)
    #expect(coordinator.canContinue)
}

@MainActor
@Test
func qaDeliveryWithoutAuthorizedFixtureFailsClosed() async throws {
    let root = URL(fileURLWithPath: "/tmp/zoid-onboarding-delivery-\(UUID().uuidString)")
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let service = OnboardingDeliveryTestService(
        runtimeEnvironment: runtime,
        fixtureAdapter: nil
    )

    let result = await service.run()

    #expect(result.state == .unavailable)
    #expect(result.message.contains("No production notification API was used"))
}

@MainActor
@Test
func realStorePersistsExactResumeStepAcrossCoordinatorRestart() async throws {
    let root = URL(fileURLWithPath: "/tmp/zoid-onboarding-restart-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let first = OnboardingCoordinator(store: OnboardingProgressStore(runtimeEnvironment: runtime))

    try await first.continueFromCurrentStep()
    let restarted = OnboardingCoordinator(
        store: OnboardingProgressStore(runtimeEnvironment: runtime)
    )

    #expect(restarted.progress.currentStep == .localPrivacy)
    #expect(restarted.progress.persistenceRevision == 1)
    #expect(restarted.route == .onboarding)
}

@MainActor
@Test
func gamingBoundaryMustPersistBeforeTheStepCompletes() async throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.gamingPolicy))
    let policyRecorder = PolicyRecorder()
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )

    coordinator.gamingPolicy = .firm
    try await coordinator.continueFromCurrentStep()

    #expect(policyRecorder.policy.gaming == GamingPolicy(
        dailyBudgetMinutes: 30,
        priorityTaskRewardMinutes: 30
    ))
    #expect(coordinator.progress.currentStep == .coachingMode)
}

@MainActor
@Test
func durablePolicyReceiptReplaysAfterProgressSaveFailure() async throws {
    let store = FailFirstProgressSaveStore(progress: try progressAt(.activityClassification))
    let policyRecorder = PolicyRecorder()
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )
    coordinator.setClassification(.work, for: "Terminal")

    await #expect(throws: (any Error).self) {
        try await coordinator.continueFromCurrentStep()
    }
    #expect(policyRecorder.version == 1)
    #expect(coordinator.progress.currentStep == .activityClassification)

    try await coordinator.continueFromCurrentStep()

    #expect(policyRecorder.version == 1)
    #expect(policyRecorder.applyCallCount == 2)
    #expect(coordinator.progress.currentStep == .schedule)
    #expect(coordinator.progress.completedEffects.map(\.step) == [.activityClassification])
}

@MainActor
@Test
func twoWindowsWithTheSameDraftShareOneEffectAndReconcileProgress() async throws {
    let store = CASRecordingOnboardingStore(progress: try progressAt(.activityClassification))
    let policyRecorder = PolicyRecorder()
    let first = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )
    let second = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )
    first.setClassification(.work, for: "Terminal")
    second.setClassification(.work, for: "Terminal")

    try await first.continueFromCurrentStep()
    try await second.continueFromCurrentStep()

    #expect(policyRecorder.version == 1)
    #expect(policyRecorder.applyCallCount == 2)
    #expect(second.progress.currentStep == .schedule)
    #expect(first.progress.completedEffects == second.progress.completedEffects)
}

@MainActor
@Test
func twoWindowsWithDifferentDraftsCannotOverwriteTheWinner() async throws {
    let store = CASRecordingOnboardingStore(progress: try progressAt(.activityClassification))
    let policyRecorder = PolicyRecorder()
    let first = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )
    let stale = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(policyRecorder: policyRecorder)
    )
    first.setClassification(.work, for: "Terminal")
    stale.setClassification(.gaming, for: "Terminal")

    try await first.continueFromCurrentStep()
    await #expect(throws: PolicyStoreError.staleVersion(expected: 0, actual: 1)) {
        try await stale.continueFromCurrentStep()
    }

    #expect(policyRecorder.version == 1)
    #expect(policyRecorder.policy.behavior.choice(for: "Terminal") == .work)
    #expect(store.saved.currentStep == .schedule)
}

@MainActor
@Test
func coachingStepDoesNotPersistProgressBeforePolicyIsDurable() async throws {
    let initial = try progressAt(.coachingMode)
    let store = CASRecordingOnboardingStore(progress: initial)
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(failPolicyMutation: true)
    )
    coordinator.selectCoachingMode(.optionalAI)

    await #expect(throws: SagaTestError.injected) {
        try await coordinator.continueFromCurrentStep()
    }

    #expect(store.saved.currentStep == .coachingMode)
    #expect(store.saved.coachingMode == nil)
    #expect(!store.saved.completedSteps.contains(.coachingMode))
    #expect(coordinator.progress.currentStep == .coachingMode)
}

@MainActor
private final class RecordingOnboardingStore: OnboardingProgressPersisting {
    var saved: OnboardingProgress?

    init(progress: OnboardingProgress? = nil) {
        saved = progress
    }

    func load() throws -> OnboardingProgress {
        if let saved { return saved }
        let fresh = try OnboardingProgress()
        saved = fresh
        return fresh
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
private final class CASRecordingOnboardingStore: OnboardingProgressPersisting {
    var saved: OnboardingProgress

    init(progress: OnboardingProgress) {
        saved = progress
    }

    func load() throws -> OnboardingProgress { saved }

    func save(_ progress: OnboardingProgress) throws -> OnboardingProgress {
        guard progress.persistenceRevision == saved.persistenceRevision else {
            throw OnboardingProgressStoreError.staleRevision(
                expected: saved.persistenceRevision,
                actual: progress.persistenceRevision
            )
        }
        saved = try progress.withPersistenceRevisionForAppTests(saved.persistenceRevision + 1)
        return saved
    }
}

@MainActor
private final class FailFirstProgressSaveStore: OnboardingProgressPersisting {
    private(set) var saved: OnboardingProgress
    private var shouldFail = true

    init(progress: OnboardingProgress) {
        saved = progress
    }

    func load() throws -> OnboardingProgress { saved }

    func save(_ progress: OnboardingProgress) throws -> OnboardingProgress {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        saved = try progress.withPersistenceRevisionForAppTests(saved.persistenceRevision + 1)
        return saved
    }
}

@MainActor
private final class StaleOnceOnboardingStore: OnboardingProgressPersisting {
    private var latest = try! OnboardingProgress()
    private var shouldFail = true

    func load() throws -> OnboardingProgress { latest }

    func save(_ progress: OnboardingProgress) throws -> OnboardingProgress {
        if shouldFail {
            shouldFail = false
            var replacement = latest
            try replacement.completeCurrentStep(at: Date(timeIntervalSince1970: 20))
            latest = try replacement.withPersistenceRevisionForAppTests(1)
            throw OnboardingProgressStoreError.staleRevision(expected: 1, actual: 0)
        }
        latest = progress
        return progress
    }
}

@MainActor
private final class PolicyRecorder {
    var policy = UserPolicy.defaults()
    var version = 0
    var receipts: [String: PolicyMutationReceipt] = [:]
    var applyCallCount = 0

    var versionedPolicy: VersionedUserPolicy? {
        guard version > 0 else { return nil }
        return VersionedUserPolicy(
            version: version,
            policy: policy,
            createdAtUTC: Date(timeIntervalSince1970: TimeInterval(version)),
            isActive: true
        )
    }

    func apply(_ request: PolicyMutationRequest) throws -> PolicyMutationReceipt {
        applyCallCount += 1
        if let receipt = receipts[request.requestID] {
            let digest = try PolicyMutationRequest.canonicalPayloadDigest(for: request.policy)
            guard receipt.payloadDigest == digest, receipt.origin == request.origin else {
                throw PolicyStoreError.idempotencyConflict(request.requestID)
            }
            return PolicyMutationReceipt(
                requestID: receipt.requestID,
                payloadDigest: receipt.payloadDigest,
                expectedVersion: receipt.expectedVersion,
                resultingVersion: receipt.resultingVersion,
                origin: receipt.origin,
                replayed: true
            )
        }
        guard request.expectedVersion == version else {
            throw PolicyStoreError.staleVersion(expected: request.expectedVersion, actual: version)
        }
        version += 1
        policy = request.policy
        let receipt = try successfulPolicyMutation(request, resultingVersion: version)
        receipts[request.requestID] = receipt
        return receipt
    }
}

@MainActor
private final class PermissionRequestGate {
    private var continuation: CheckedContinuation<SourceHealth, Never>?

    func wait() async -> SourceHealth {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume(with health: SourceHealth) {
        continuation?.resume(returning: health)
        continuation = nil
    }
}

@MainActor
private final class DeliveryRequestGate {
    private var continuation: CheckedContinuation<OnboardingDeliveryResult, Never>?

    func wait() async -> OnboardingDeliveryResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume(with result: OnboardingDeliveryResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class ReminderListRequestGate {
    private var continuations: [CheckedContinuation<ReminderListLoad, Never>] = []

    var requestCount: Int { continuations.count }

    func wait() async -> ReminderListLoad {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resumeRequest(_ index: Int, with result: ReminderListLoad) {
        continuations[index].resume(returning: result)
    }
}

@MainActor
private func testDependencies(
    inventory: AppInventoryLoadResult = .init(items: [], warning: nil),
    policyRecorder: PolicyRecorder = PolicyRecorder(),
    deliveryResult: OnboardingDeliveryResult = .init(
        state: .delivered,
        message: "Delivered by test fixture"
    ),
    firstPlan: OnboardingFirstDailyPlanResult = preparedFirstPlan,
    failPolicyMutation: Bool = false
) -> OnboardingDependencies {
    OnboardingDependencies(
        inspectReminders: { SelfHealth.remindersDenied },
        requestReminders: { .init(health: SelfHealth.remindersDenied, decision: .denied) },
        inspectScreenwatch: { SelfHealth.screenwatchMissing },
        inspectScreenwatchSetup: { SelfScreenwatch.missing },
        selectScreenwatchDirectory: { _ in SelfScreenwatch.healthy },
        useDefaultScreenwatchDirectory: { SelfScreenwatch.missing },
        inspectNotifications: { SelfHealth.notificationsDenied },
        requestNotifications: { .init(health: SelfHealth.notificationsDenied, decision: .denied) },
        loadInventory: { inventory },
        testDelivery: { deliveryResult },
        loadPolicy: { policyRecorder.versionedPolicy },
        applyPolicyMutation: {
            if failPolicyMutation { throw SagaTestError.injected }
            return try policyRecorder.apply($0)
        },
        prepareFirstDailyPlan: { firstPlan },
        openSystemSettings: { _ in true }
    )
}

private enum SagaTestError: Error {
    case injected
}

private func successfulPolicyMutation(
    _ request: PolicyMutationRequest,
    resultingVersion: Int? = nil
) throws -> PolicyMutationReceipt {
    PolicyMutationReceipt(
        requestID: request.requestID,
        payloadDigest: try PolicyMutationRequest.canonicalPayloadDigest(for: request.policy),
        expectedVersion: request.expectedVersion,
        resultingVersion: resultingVersion ?? request.expectedVersion + 1,
        origin: request.origin,
        replayed: false
    )
}

private let preparedFirstPlan = OnboardingFirstDailyPlanResult(
    state: .prepared,
    items: [
        .init(
            id: "first-plan-task",
            title: "Choose the first meaningful action",
            estimateMinutes: 25,
            isMainObjective: true
        )
    ],
    message: "One visible plan item is ready."
)

private enum SelfScreenwatch {
    static let missing = ScreenwatchSetupStatus(
        source: .defaultLocation,
        health: .missing,
        continuation: .degraded,
        repair: .chooseFolder,
        summary: "Today’s Screenwatch telemetry stream was not found.",
        evidence: "Planning remains available without behavior coaching.",
        validRecordCount: 0
    )
    static let healthy = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .healthy,
        continuation: .ready,
        repair: .none,
        summary: "Screenwatch telemetry is connected.",
        evidence: "Schema-valid local records were found.",
        validRecordCount: 2
    )
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
    static let remindersHealthy = SourceHealth(
        id: .reminders,
        title: "Apple Reminders",
        eyebrow: "Intent",
        state: .healthy,
        detail: "Reminders are connected",
        evidence: "Fixture",
        actionTitle: "Inspect"
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

private func progressAt(
    _ target: OnboardingStep,
    notificationDecision: OnboardingAccessDecision = .deferred
) throws -> OnboardingProgress {
    var progress = try OnboardingProgress()
    while progress.currentStep != target {
        if [.reminders, .screenwatch, .notifications].contains(progress.currentStep) {
            let decision = progress.currentStep == .notifications
                ? notificationDecision
                : .deferred
            try progress.recordAccessDecision(decision, for: progress.currentStep)
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
            flowID: flowID,
            persistenceRevision: revision,
            currentStep: currentStep,
            completedSteps: completedSteps,
            coachingMode: coachingMode,
            remindersAccess: remindersAccess,
            screenwatchAccess: screenwatchAccess,
            notificationAccess: notificationAccess,
            reminderListDecisions: reminderListDecisions,
            emptyReminderListFallbackConfirmed: emptyReminderListFallbackConfirmed,
            completedEffects: completedEffects,
            finishedAt: finishedAt
        )
    }
}
