import Foundation
import Testing
import ZoidCoachCore

@Test
func onboardingProgressAdvancesInOrderAndRequiresAnExplicitCoachingMode() throws {
    var progress = try OnboardingProgress()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(progress.currentStep == .welcome)
    try progress.completeCurrentStep(at: now)
    #expect(progress.currentStep == .localPrivacy)

    for step in OnboardingStep.allCases.dropFirst().dropLast(3) {
        #expect(progress.currentStep == step)
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

    for step in OnboardingStep.allCases {
        #expect(progress.currentStep == step)
        if step == .coachingMode {
            progress.chooseCoachingMode(.rulesOnly)
        }
        try progress.completeCurrentStep(at: finishedAt)
    }

    #expect(progress.isFinished)
    #expect(progress.finishedAt == finishedAt)
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
    try firstProcess.save(progress)

    let restartedProcess = OnboardingProgressStore(runtimeEnvironment: runtime)
    let resumed = try restartedProcess.load()

    #expect(resumed == progress)
    #expect(resumed.currentStep == .reminders)
    #expect(restartedProcess.fileURL.path.hasPrefix(qaRoot.path + "/"))
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

    #expect(throws: OnboardingProgressError.self) {
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
