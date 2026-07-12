import Foundation
import Testing
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func legacyOnboardingWithoutEffectReceiptsStillDecodes() throws {
    let legacy = """
    {
      "version": 1,
      "persistenceRevision": 9,
      "currentStep": "schedule",
      "completedSteps": ["welcome", "localPrivacy", "reminders", "screenwatch", "notifications", "applicationInventory", "activityClassification"],
      "remindersAccess": "deferred",
      "screenwatchAccess": "unavailable",
      "notificationAccess": "denied"
    }
    """

    let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: Data(legacy.utf8))

    #expect(decoded.version == 1)
    #expect(decoded.currentStep == .schedule)
    #expect(decoded.completedEffects.isEmpty)
}

@Test
func onboardingProgressAdvancesInOrderAndRequiresAnExplicitCoachingMode() throws {
    var progress = try OnboardingProgress()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(progress.currentStep == .welcome)
    try progress.completeCurrentStep(at: now)
    #expect(progress.currentStep == .localPrivacy)

    for step in OnboardingProgress.stepSequence.dropFirst().dropLast(3) {
        #expect(progress.currentStep == step)
        if [.reminders, .screenwatch, .notifications].contains(step) {
            try progress.recordAccessDecision(.deferred, for: step)
        }
        try progress.completeCurrentStep(at: now)
    }
    #expect(progress.currentStep == .coachingMode)
    #expect(throws: OnboardingProgressError.coachingModeRequired) {
        try progress.completeCurrentStep(at: now)
    }
    progress.chooseCoachingMode(.rulesOnly)
    try progress.completeCurrentStep(at: now)
    #expect(progress.currentStep == .deliveryTest)
}

@Test
func onboardingCanNavigateBackButCannotSkipAhead() throws {
    var progress = try OnboardingProgress()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try progress.completeCurrentStep(at: now)
    try progress.completeCurrentStep(at: now)

    try progress.navigate(to: .welcome)
    #expect(progress.currentStep == .welcome)
    #expect(throws: OnboardingProgressError.stepNotReachable(.screenwatch)) {
        try progress.navigate(to: .screenwatch)
    }
}

@Test
func onboardingOnlyFinishesAfterTheFirstDailyPlan() throws {
    var progress = try OnboardingProgress()
    let finishedAt = Date(timeIntervalSince1970: 1_800_000_000)

    for step in OnboardingProgress.stepSequence {
        #expect(progress.currentStep == step)
        if [.reminders, .screenwatch, .notifications].contains(step) {
            try progress.recordAccessDecision(.denied, for: step)
        }
        if step == .coachingMode {
            progress.chooseCoachingMode(.rulesOnly)
        }
        try progress.completeCurrentStep(at: finishedAt)
    }

    #expect(progress.isFinished)
    #expect(progress.finishedAt == finishedAt)
    #expect(throws: OnboardingProgressError.alreadyFinished) {
        try progress.navigate(to: .welcome)
    }
    #expect(throws: OnboardingProgressError.alreadyFinished) {
        try progress.completeCurrentStep(at: finishedAt)
    }
}

@Test
func onboardingStoreResumesTheExactPersistedStepAcrossRestarts() throws {
    let qaRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-onboarding-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: qaRoot) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", qaRoot.path],
        processEnvironment: [:]
    ).environment
    let firstProcess = OnboardingProgressStore(runtimeEnvironment: runtime)
    var progress = try firstProcess.load()
    try progress.completeCurrentStep(at: Date())
    try progress.completeCurrentStep(at: Date())
    try progress.recordAccessDecision(.denied, for: .reminders)
    progress = try firstProcess.save(progress)

    let restartedProcess = OnboardingProgressStore(runtimeEnvironment: runtime)
    let resumed = try restartedProcess.load()

    #expect(resumed == progress)
    #expect(resumed.currentStep == .reminders)
    #expect(resumed.remindersAccess == .denied)
    #expect(restartedProcess.fileURL.path.hasPrefix(qaRoot.path + "/"))
}

@Test
func onboardingStoreResumesReminderListDraftAcrossRestarts() throws {
    let qaRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-onboarding-list-draft-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: qaRoot) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", qaRoot.path],
        processEnvironment: [:]
    ).environment
    let firstProcess = OnboardingProgressStore(runtimeEnvironment: runtime)
    var progress = try firstProcess.load()
    try progress.completeCurrentStep(at: Date())
    try progress.completeCurrentStep(at: Date())
    try progress.recordAccessDecision(.granted, for: .reminders)
    progress.setReminderListDecision(true, listID: "work-id")
    progress.setReminderListDecision(false, listID: "personal-id")
    progress = try firstProcess.save(progress)

    let resumed = try OnboardingProgressStore(runtimeEnvironment: runtime).load()

    #expect(resumed.reminderListDecisions == [
        ReminderListDecision(listID: "personal-id", isIncluded: false),
        ReminderListDecision(listID: "work-id", isIncluded: true),
    ])
}

@Test
func onboardingStoreRejectsCorruptProgressWithoutOverwritingIt() throws {
    let qaRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-onboarding-corrupt-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: qaRoot) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", qaRoot.path],
        processEnvironment: [:]
    ).environment
    let store = OnboardingProgressStore(runtimeEnvironment: runtime)
    try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corrupt = Data("not-json".utf8)
    try corrupt.write(to: store.fileURL)

    #expect(throws: OnboardingProgressStoreError.corruptProgress(path: store.fileURL.path)) {
        try store.load()
    }
    #expect(try Data(contentsOf: store.fileURL) == corrupt)
}

@Test
func onboardingProgressRejectsSkippedOrUnreachablePersistedState() {
    #expect(throws: OnboardingProgressError.completedStepsNotContiguous) {
        try OnboardingProgress(
            currentStep: .localPrivacy,
            completedSteps: [.welcome, .reminders]
        )
    }
    #expect(throws: OnboardingProgressError.invalidCurrentStep) {
        try OnboardingProgress(currentStep: .screenwatch, completedSteps: [.welcome])
    }
}

@Test
func onboardingPersistsPermissionDenialAndDegradedContinuationDecisions() throws {
    var progress = try OnboardingProgress()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try progress.completeCurrentStep(at: now)
    try progress.completeCurrentStep(at: now)

    #expect(throws: OnboardingProgressError.accessDecisionRequired(.reminders)) {
        try progress.completeCurrentStep(at: now)
    }
    try progress.recordAccessDecision(.denied, for: .reminders)
    try progress.completeCurrentStep(at: now)
    try progress.recordAccessDecision(.unavailable, for: .screenwatch)
    try progress.completeCurrentStep(at: now)
    try progress.recordAccessDecision(.deferred, for: .notifications)
    try progress.completeCurrentStep(at: now)

    #expect(progress.remindersAccess == .denied)
    #expect(progress.screenwatchAccess == .unavailable)
    #expect(progress.notificationAccess == .deferred)
    #expect(progress.currentStep == .applicationInventory)
}

@Test
func onboardingProgressRejectsContradictoryTerminalState() {
    var completed = OnboardingProgress.stepSequence
    completed.removeLast()
    #expect(throws: OnboardingProgressError.stepsIncomplete) {
        try OnboardingProgress(
            currentStep: .firstDailyPlan,
            completedSteps: completed,
            coachingMode: .rulesOnly,
            remindersAccess: .granted,
            screenwatchAccess: .granted,
            notificationAccess: .granted,
            finishedAt: Date()
        )
    }
    #expect(throws: OnboardingProgressError.stepsIncomplete) {
        try OnboardingProgress(
            currentStep: .firstDailyPlan,
            completedSteps: OnboardingProgress.stepSequence,
            coachingMode: .rulesOnly,
            remindersAccess: .granted,
            screenwatchAccess: .granted,
            notificationAccess: .granted
        )
    }
}
