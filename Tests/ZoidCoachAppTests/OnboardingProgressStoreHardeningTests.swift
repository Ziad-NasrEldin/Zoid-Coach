import Foundation
import Testing
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func onboardingVersionOneSequenceIsExplicitAndComplete() {
    #expect(OnboardingProgress.stepSequence == [
        .welcome,
        .localPrivacy,
        .reminders,
        .screenwatch,
        .notifications,
        .applicationInventory,
        .activityClassification,
        .schedule,
        .gamingPolicy,
        .coachingMode,
        .deliveryTest,
        .firstDailyPlan,
    ])
    #expect(Set(OnboardingProgress.stepSequence) == Set(OnboardingStep.allCases))
}

@Test
func onboardingDecodesLegacyVersionOneProgressWithoutNewOptionalAccessFields() throws {
    let legacy = Data(#"""
    {
        "version": 1,
        "currentStep": "reminders",
        "completedSteps": ["welcome", "localPrivacy"]
    }
    """#.utf8)

    let progress = try JSONDecoder().decode(OnboardingProgress.self, from: legacy)

    try progress.validate()
    #expect(progress.currentStep == .reminders)
    #expect(progress.remindersAccess == nil)
    #expect(progress.screenwatchAccess == nil)
    #expect(progress.notificationAccess == nil)
}

@Test
func onboardingPersistsEveryAccessDecisionAcrossAStoreRestart() throws {
    let fixture = try OnboardingStoreFixture(name: "access-restart")
    defer { fixture.remove() }
    let firstStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var progress = try OnboardingProgress()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try progress.completeCurrentStep(at: now)
    try progress.completeCurrentStep(at: now)
    try progress.recordAccessDecision(.denied, for: .reminders)
    try progress.completeCurrentStep(at: now)
    try progress.recordAccessDecision(.unavailable, for: .screenwatch)
    try progress.completeCurrentStep(at: now)
    try progress.recordAccessDecision(.deferred, for: .notifications)
    try progress.completeCurrentStep(at: now)
    try firstStore.save(progress)

    let restarted = try OnboardingProgressStore(runtimeEnvironment: fixture.runtime).load()

    #expect(restarted == progress)
    #expect(restarted.remindersAccess == .denied)
    #expect(restarted.screenwatchAccess == .unavailable)
    #expect(restarted.notificationAccess == .deferred)
}

@Test
func onboardingFailedAtomicWritePreservesTheLastCommittedProgress() throws {
    let fixture = try OnboardingStoreFixture(name: "write-failure")
    defer { fixture.remove() }
    let baselineStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var baseline = try OnboardingProgress()
    try baseline.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
    try baselineStore.save(baseline)
    var replacement = baseline
    try replacement.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))
    let failingStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        storageCheckpoint: { checkpoint in
            if checkpoint == .beforeStateCommit { throw OnboardingStoreInterruption.injected }
        }
    )

    #expect(throws: OnboardingStoreInterruption.injected) {
        try failingStore.save(replacement)
    }
    #expect(try baselineStore.load() == baseline)
}

@Test
func onboardingCorruptionRecoveryQuarantinesExactBytesAndPersistsAReplacement() throws {
    let fixture = try OnboardingStoreFixture(name: "corrupt-recovery")
    defer { fixture.remove() }
    let recoveryStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset
    )
    try FileManager.default.createDirectory(
        at: recoveryStore.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corruptBytes = Data([0x00, 0xFF, 0x7B, 0x01])
    try corruptBytes.write(to: recoveryStore.fileURL)

    let recovered = try recoveryStore.load()

    #expect(recovered == (try OnboardingProgress()))
    #expect(try Data(contentsOf: recoveryStore.corruptFileURL) == corruptBytes)
    #expect(!FileManager.default.fileExists(atPath: recoveryStore.recoveryFileURL.path))
    #expect(try OnboardingProgressStore(runtimeEnvironment: fixture.runtime).load() == recovered)
}

@Test
func onboardingRecoveryResumesAfterQuarantineWithoutLosingCorruptBytes() throws {
    let fixture = try OnboardingStoreFixture(name: "recovery-resume")
    defer { fixture.remove() }
    let interruptedStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset,
        storageCheckpoint: { checkpoint in
            if checkpoint == .corruptStateQuarantined {
                throw OnboardingStoreInterruption.injected
            }
        }
    )
    try FileManager.default.createDirectory(
        at: interruptedStore.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corruptBytes = Data("damaged-onboarding".utf8)
    try corruptBytes.write(to: interruptedStore.fileURL)

    #expect(throws: OnboardingStoreInterruption.injected) {
        try interruptedStore.load()
    }
    #expect(try Data(contentsOf: interruptedStore.corruptFileURL) == corruptBytes)
    #expect(FileManager.default.fileExists(atPath: interruptedStore.recoveryFileURL.path))

    let resumed = try OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset
    ).load()
    #expect(resumed == (try OnboardingProgress()))
    #expect(try Data(contentsOf: interruptedStore.corruptFileURL) == corruptBytes)
    #expect(!FileManager.default.fileExists(atPath: interruptedStore.recoveryFileURL.path))
}

@Test
func onboardingStoreRejectsIntermediateAndFinalDirectorySymlinks() throws {
    let intermediate = try OnboardingStoreFixture(name: "intermediate-symlink")
    defer { intermediate.remove() }
    let outsideIntermediate = intermediate.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideIntermediate, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: intermediate.runtime.applicationSupportRoot)
    try FileManager.default.createSymbolicLink(
        at: intermediate.runtime.applicationSupportRoot,
        withDestinationURL: outsideIntermediate
    )
    let intermediateStore = OnboardingProgressStore(runtimeEnvironment: intermediate.runtime)
    #expect(throws: OnboardingProgressStoreError.unsafeFilesystemEntry("Application Support")) {
        try intermediateStore.save(try OnboardingProgress())
    }

    let final = try OnboardingStoreFixture(name: "final-symlink")
    defer { final.remove() }
    let outsideFinal = final.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideFinal, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: final.runtime.applicationSupportRoot,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: final.runtime.applicationSupportRoot.appendingPathComponent("Zoid Coach"),
        withDestinationURL: outsideFinal
    )
    let finalStore = OnboardingProgressStore(runtimeEnvironment: final.runtime)
    #expect(throws: OnboardingProgressStoreError.unsafeFilesystemEntry("Zoid Coach")) {
        try finalStore.save(try OnboardingProgress())
    }
}

@Test
func onboardingStoreRejectsTheFinalStateFileSymlink() throws {
    let fixture = try OnboardingStoreFixture(name: "state-file-symlink")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    let outside = fixture.root.appendingPathComponent("outside-progress.json")
    let outsideBytes = Data("outside".utf8)
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try outsideBytes.write(to: outside)
    try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: outside)

    #expect(throws: OnboardingProgressStoreError.unsafeFilesystemEntry("onboarding-progress.json")) {
        try store.load()
    }
    #expect(try Data(contentsOf: outside) == outsideBytes)
}

@Test
func onboardingConcurrentStoreInstancesAlwaysLeaveAValidWholeState() async throws {
    let fixture = try OnboardingStoreFixture(name: "concurrent-instances")
    defer { fixture.remove() }
    let first = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    let second = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var welcomeComplete = try OnboardingProgress()
    try welcomeComplete.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
    var privacyComplete = welcomeComplete
    try privacyComplete.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0 ..< 40 {
            let store = index.isMultiple(of: 2) ? first : second
            let progress = index.isMultiple(of: 3) ? welcomeComplete : privacyComplete
            group.addTask { try store.save(progress) }
        }
        try await group.waitForAll()
    }

    let result = try first.load()
    try result.validate()
    #expect(result == welcomeComplete || result == privacyComplete)
}

@Test
func onboardingResetWaitsForAnInFlightSaveAndWinsWhenRequestedAfterIt() async throws {
    let fixture = try OnboardingStoreFixture(name: "save-reset-order")
    defer { fixture.remove() }
    let baselineStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var baseline = try OnboardingProgress()
    try baseline.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
    try baselineStore.save(baseline)
    var replacement = baseline
    try replacement.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))
    let gate = OnboardingCommitGate()
    let savingStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        storageCheckpoint: gate.checkpoint
    )
    let resetStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)

    let saveTask = Task.detached { try savingStore.save(replacement) }
    #expect(gate.waitUntilSaveReachedCommit())
    let resetCompleted = OnboardingCompletionFlag()
    let resetTask = Task.detached {
        try resetStore.reset()
        resetCompleted.markCompleted()
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(!resetCompleted.isCompleted)
    gate.allowCommit()
    try await saveTask.value
    try await resetTask.value

    #expect(try baselineStore.load() == (try OnboardingProgress()))
}

@Test
func onboardingStoreWaitsForAChildProcessAdvisoryLock() async throws {
    let fixture = try OnboardingStoreFixture(name: "child-lock")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    try store.save(try OnboardingProgress())
    let directory = store.fileURL.deletingLastPathComponent()
    let ready = fixture.root.appendingPathComponent("child-lock-ready")
    let release = fixture.root.appendingPathComponent("child-lock-release")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    child.arguments = [
        "-c",
        "import fcntl, os, pathlib, sys, time\nfd=os.open(sys.argv[1], os.O_RDONLY)\nfcntl.flock(fd, fcntl.LOCK_EX)\npathlib.Path(sys.argv[2]).write_text('ready')\nwhile not pathlib.Path(sys.argv[3]).exists(): time.sleep(0.01)\nfcntl.flock(fd, fcntl.LOCK_UN)\nos.close(fd)",
        directory.path,
        ready.path,
        release.path,
    ]
    try child.run()
    defer { if child.isRunning { child.terminate() } }
    for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: ready.path) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(FileManager.default.fileExists(atPath: ready.path))
    let completion = OnboardingCompletionFlag()
    let saveTask = Task.detached {
        var progress = try OnboardingProgress()
        try progress.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(progress)
        completion.markCompleted()
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(!completion.isCompleted)
    try Data("release".utf8).write(to: release)
    child.waitUntilExit()
    try await saveTask.value
    #expect(completion.isCompleted)
    #expect(try store.load().currentStep == .localPrivacy)
}

@Test
func onboardingProductionAndQAStoresUseTheirIsolatedRuntimePaths() throws {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-onboarding-paths-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let productionSupport = container.appendingPathComponent("Production Support", isDirectory: true)
    let production = RuntimeEnvironment.production(directories: .init(
        home: container.appendingPathComponent("Home", isDirectory: true),
        applicationSupport: productionSupport
    ))
    let qaRoot = container.appendingPathComponent("QA Run", isDirectory: true)
    let qa = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", qaRoot.path],
        processEnvironment: [:],
        directories: .init(
            home: container.appendingPathComponent("Home", isDirectory: true),
            applicationSupport: productionSupport
        )
    ).environment
    let productionStore = OnboardingProgressStore(runtimeEnvironment: production)
    let qaStore = OnboardingProgressStore(runtimeEnvironment: qa)

    #expect(productionStore.fileURL.path == productionSupport.path + "/Zoid Coach/onboarding-progress.json")
    #expect(qaStore.fileURL.path == qaRoot.path + "/Application Support/Zoid Coach/onboarding-progress.json")
    #expect(productionStore.fileURL != qaStore.fileURL)
    try qaStore.save(try OnboardingProgress())
    #expect(!FileManager.default.fileExists(atPath: productionStore.fileURL.path))
}

private enum OnboardingStoreInterruption: Error, Equatable {
    case injected
}

private struct OnboardingStoreFixture {
    let root: URL
    let runtime: RuntimeEnvironment

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-onboarding-\(name)-\(UUID().uuidString)", isDirectory: true)
        runtime = try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", root.path],
            processEnvironment: [:]
        ).environment
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class OnboardingCommitGate: @unchecked Sendable {
    private let reachedCommit = DispatchSemaphore(value: 0)
    private let allowCommitSemaphore = DispatchSemaphore(value: 0)

    func checkpoint(_ checkpoint: OnboardingPersistenceCheckpoint) {
        guard checkpoint == .beforeStateCommit else { return }
        reachedCommit.signal()
        allowCommitSemaphore.wait()
    }

    func waitUntilSaveReachedCommit() -> Bool {
        reachedCommit.wait(timeout: .now() + 5) == .success
    }

    func allowCommit() {
        allowCommitSemaphore.signal()
    }
}

private final class OnboardingCompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func markCompleted() {
        lock.withLock { completed = true }
    }

    var isCompleted: Bool {
        lock.withLock { completed }
    }
}
