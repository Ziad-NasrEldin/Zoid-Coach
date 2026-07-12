import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

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
        requestReminders: { .init(health: SelfHealth.remindersDenied, decision: .denied) },
        inspectScreenwatch: { SelfHealth.screenwatchMissing },
        inspectScreenwatchSetup: { SelfScreenwatch.missing },
        selectScreenwatchDirectory: { _ in SelfScreenwatch.healthy },
        useDefaultScreenwatchDirectory: { SelfScreenwatch.missing },
        inspectNotifications: { SelfHealth.notificationsDenied },
        requestNotifications: { .init(health: SelfHealth.notificationsDenied, decision: .denied) },
        loadInventory: { .init(items: [], warning: nil) },
        testDelivery: { .init(state: .unavailable, message: "Notifications are disabled") },
        loadPolicy: { .defaults() },
        savePolicy: { _ in },
        loadGamingPolicy: { GamingPolicy() },
        saveGamingPolicy: { _ in },
        prepareFirstDailyPlan: { preparedFirstPlan },
        openSystemSettings: { _ in true }
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
        savePolicy: base.savePolicy,
        loadGamingPolicy: base.loadGamingPolicy,
        saveGamingPolicy: base.saveGamingPolicy,
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
        try coordinator.continueFromCurrentStep()
    }
    await coordinator.prepareFirstDailyPlan()
    try coordinator.continueFromCurrentStep()

    #expect(coordinator.progress.completedSteps == OnboardingProgress.stepSequence)
    #expect(coordinator.progress.isFinished)
    #expect(coordinator.route == .today)
    #expect(store.saved?.finishedAt != nil)
}

@MainActor
@Test
func deliveryStepRequiresTheTestTaskAndAUsablePromptPath() throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.deliveryTest))
    let coordinator = OnboardingCoordinator(store: store, dependencies: testDependencies())

    #expect(!coordinator.canContinue)
    coordinator.completeTestTask()
    coordinator.completeTestTask()
    #expect(coordinator.canContinue)
    try coordinator.continueFromCurrentStep()
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
    #expect(throws: (any Error).self) { try blocked.continueFromCurrentStep() }
    #expect(!blocked.progress.isFinished)

    let ready = OnboardingCoordinator(store: store, dependencies: testDependencies())
    await ready.prepareFirstDailyPlan()
    #expect(ready.canContinue)
    try ready.continueFromCurrentStep()
    #expect(ready.progress.isFinished)
    #expect(ready.route == .today)
}

@MainActor
@Test
func classificationAndScheduleAreAppliedBeforeAdvancing() throws {
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
    try coordinator.continueFromCurrentStep()
    #expect(policyRecorder.policy.behavior.choice(for: app.name) == .work)

    coordinator.workStartHour = 8
    coordinator.workEndHour = 17
    coordinator.quietStartHour = 21
    coordinator.quietEndHour = 6
    try coordinator.continueFromCurrentStep()
    #expect(policyRecorder.policy.schedule.workWindows.first?.start == LocalTime(hour: 8, minute: 0))
    #expect(policyRecorder.policy.schedule.workWindows.first?.end == LocalTime(hour: 17, minute: 0))
    #expect(policyRecorder.policy.schedule.quietHours == DailyTimeWindow(
        start: LocalTime(hour: 21, minute: 0),
        end: LocalTime(hour: 6, minute: 0)
    ))
}

@MainActor
@Test
func staleSaveRestoresLatestProgressAndOffersRetry() throws {
    let store = StaleOnceOnboardingStore()
    let coordinator = OnboardingCoordinator(store: store)

    #expect(throws: (any Error).self) {
        try coordinator.continueFromCurrentStep()
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
        savePolicy: dependencies.savePolicy,
        loadGamingPolicy: dependencies.loadGamingPolicy,
        saveGamingPolicy: dependencies.saveGamingPolicy,
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
        savePolicy: base.savePolicy,
        loadGamingPolicy: base.loadGamingPolicy,
        saveGamingPolicy: base.saveGamingPolicy,
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
        savePolicy: base.savePolicy,
        loadGamingPolicy: base.loadGamingPolicy,
        saveGamingPolicy: base.saveGamingPolicy,
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
func realStorePersistsExactResumeStepAcrossCoordinatorRestart() throws {
    let root = URL(fileURLWithPath: "/tmp/zoid-onboarding-restart-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let first = OnboardingCoordinator(store: OnboardingProgressStore(runtimeEnvironment: runtime))

    try first.continueFromCurrentStep()
    let restarted = OnboardingCoordinator(
        store: OnboardingProgressStore(runtimeEnvironment: runtime)
    )

    #expect(restarted.progress.currentStep == .localPrivacy)
    #expect(restarted.progress.persistenceRevision == 1)
    #expect(restarted.route == .onboarding)
}

@MainActor
@Test
func gamingBoundaryMustPersistBeforeTheStepCompletes() throws {
    let store = RecordingOnboardingStore(progress: try progressAt(.gamingPolicy))
    let gamingRecorder = GamingPolicyRecorder()
    let coordinator = OnboardingCoordinator(
        store: store,
        dependencies: testDependencies(gamingRecorder: gamingRecorder)
    )

    coordinator.gamingPolicy = .firm
    try coordinator.continueFromCurrentStep()

    #expect(gamingRecorder.policy == GamingPolicy(
        dailyBudgetMinutes: 30,
        priorityTaskRewardMinutes: 30
    ))
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
}

@MainActor
private final class GamingPolicyRecorder {
    var policy = GamingPolicy()
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
private func testDependencies(
    inventory: AppInventoryLoadResult = .init(items: [], warning: nil),
    policyRecorder: PolicyRecorder = PolicyRecorder(),
    gamingRecorder: GamingPolicyRecorder = GamingPolicyRecorder(),
    deliveryResult: OnboardingDeliveryResult = .init(
        state: .delivered,
        message: "Delivered by test fixture"
    ),
    firstPlan: OnboardingFirstDailyPlanResult = preparedFirstPlan
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
        loadPolicy: { policyRecorder.policy },
        savePolicy: { policyRecorder.policy = $0 },
        loadGamingPolicy: { gamingRecorder.policy },
        saveGamingPolicy: { gamingRecorder.policy = $0 },
        prepareFirstDailyPlan: { firstPlan },
        openSystemSettings: { _ in true }
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
