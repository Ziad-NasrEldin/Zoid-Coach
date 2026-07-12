import Darwin
import Foundation
import Testing
import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func onboardingStoreAcceptsTheTrustedMacOSTemporaryDirectoryAlias() throws {
    let runRoot = URL(
        fileURLWithPath: "/tmp/zoid-onboarding-alias-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: runRoot) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", runRoot.path],
        processEnvironment: [:]
    ).environment
    let store = try OnboardingProgressStore(runtimeEnvironment: runtime)

    let saved = try store.save(OnboardingProgress())

    #expect(try store.load() == saved)
    #expect(store.fileURL.path.hasSuffix("Zoid Coach/onboarding-progress.json"))
}

@Test
func downstreamPackagesCompileDocumentedImportsAndRejectTheRemovedCoreOnlyPath() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-onboarding-consumers-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let successfulPackage = container.appendingPathComponent("SuccessfulConsumers", isDirectory: true)
    try writeDownstreamPackage(
        at: successfulPackage,
        repositoryRoot: repositoryRoot,
        targets: [
            (
                name: "CoreProductConsumer",
                product: "ZoidCoachCore",
                source: """
                import ZoidCoachCore
                import ZoidCoachInfrastructure
                let store: OnboardingProgressStore? = nil
                print(store as Any)
                """
            ),
            (
                name: "InfrastructureProductConsumer",
                product: "ZoidCoachInfrastructure",
                source: """
                import ZoidCoachCore
                import ZoidCoachInfrastructure
                let store: OnboardingProgressStore? = nil
                print(store as Any)
                """
            ),
        ]
    )
    let successfulBuild = try runDownstreamBuild(at: successfulPackage)
    #expect(successfulBuild.status == 0, Comment(rawValue: successfulBuild.errorOutput))

    let coreOnlyPackage = container.appendingPathComponent("CoreOnlyConsumer", isDirectory: true)
    try writeDownstreamPackage(
        at: coreOnlyPackage,
        repositoryRoot: repositoryRoot,
        targets: [(
            name: "CoreOnlyConsumer",
            product: "ZoidCoachCore",
            source: """
            import ZoidCoachCore
            let store: OnboardingProgressStore? = nil
            print(store as Any)
            """
        )]
    )
    let rejectedBuild = try runDownstreamBuild(at: coreOnlyPackage)
    #expect(rejectedBuild.status != 0)
    #expect(rejectedBuild.errorOutput.contains("cannot find type 'OnboardingProgressStore' in scope"))
}

@Test
func descriptorDirectoryCreationSyncsEachParentImmediatelyAfterMkdir() throws {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-descriptor-sync-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let root = container.appendingPathComponent("Application Support", isDirectory: true)
    let recorder = DescriptorCheckpointRecorder()

    _ = try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
        rootURL: root,
        directoryName: "Zoid Coach",
        createRootIfMissing: true,
        checkpoint: recorder.record,
        unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
        filesystemError: OnboardingProgressStoreError.filesystemOperation
    )

    #expect(recorder.values == [
        .createdRootComponent("Application Support"),
        .syncedRootComponentParent("Application Support"),
        .createdStateDirectory("Zoid Coach"),
        .syncedStateDirectoryParent("Zoid Coach"),
    ])
}

@Test
func descriptorDirectoryCreationFailsBeforeUseWhenParentSyncFails() throws {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-descriptor-sync-failure-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let root = container.appendingPathComponent("Application Support", isDirectory: true)
    let recorder = DescriptorCheckpointRecorder()
    let operations = DescriptorRelativeStateDirectoryOperations(
        createDirectory: DescriptorRelativeStateDirectoryOperations.live.createDirectory,
        syncDirectory: { _ in EIO }
    )

    #expect(throws: OnboardingProgressStoreError.filesystemOperation(
        "sync root component Application Support",
        EIO
    )) {
        try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
            rootURL: root,
            directoryName: "Zoid Coach",
            createRootIfMissing: true,
            operations: operations,
            checkpoint: recorder.record,
            unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
            filesystemError: OnboardingProgressStoreError.filesystemOperation
        )
    }
    #expect(recorder.values == [.createdRootComponent("Application Support")])
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Zoid Coach").path))
}

@Test
func descriptorDirectoryCreationSurfacesInjectedMkdirFailureWithoutCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-descriptor-mkdir-failure-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let recorder = DescriptorCheckpointRecorder()
    let operations = DescriptorRelativeStateDirectoryOperations(
        createDirectory: { _, _, _ in EACCES },
        syncDirectory: DescriptorRelativeStateDirectoryOperations.live.syncDirectory
    )

    #expect(throws: OnboardingProgressStoreError.filesystemOperation(
        "create state directory",
        EACCES
    )) {
        try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
            rootURL: root,
            directoryName: "Zoid Coach",
            operations: operations,
            checkpoint: recorder.record,
            unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
            filesystemError: OnboardingProgressStoreError.filesystemOperation
        )
    }
    #expect(recorder.values.isEmpty)
}

@Test
func descriptorRootCreationRetriesWithParentSyncAfterFailOnceFsync() throws {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-root-sync-retry-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let root = container.appendingPathComponent("Application Support", isDirectory: true)
    let failOnce = DescriptorFailOnceSync()
    let operations = DescriptorRelativeStateDirectoryOperations(
        createDirectory: DescriptorRelativeStateDirectoryOperations.live.createDirectory,
        syncDirectory: failOnce.sync
    )

    #expect(throws: OnboardingProgressStoreError.filesystemOperation(
        "sync root component Application Support",
        EIO
    )) {
        try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
            rootURL: root,
            directoryName: "Zoid Coach",
            createRootIfMissing: true,
            operations: operations,
            unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
            filesystemError: OnboardingProgressStoreError.filesystemOperation
        )
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))

    let retryRecorder = DescriptorCheckpointRecorder()
    let storage = try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
        rootURL: root,
        directoryName: "Zoid Coach",
        createRootIfMissing: true,
        operations: operations,
        checkpoint: retryRecorder.record,
        unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
        filesystemError: OnboardingProgressStoreError.filesystemOperation
    )
    try storage.writeAtomic(Data("durable".utf8), name: "state.json")

    #expect(retryRecorder.values == [
        .createdRootComponent("Application Support"),
        .syncedRootComponentParent("Application Support"),
        .createdStateDirectory("Zoid Coach"),
        .syncedStateDirectoryParent("Zoid Coach"),
    ])
    #expect(try storage.read("state.json") == Data("durable".utf8))
}

@Test
func descriptorStateDirectoryRetriesWithParentSyncAfterFailOnceFsync() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-state-sync-retry-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let failOnce = DescriptorFailOnceSync()
    let operations = DescriptorRelativeStateDirectoryOperations(
        createDirectory: DescriptorRelativeStateDirectoryOperations.live.createDirectory,
        syncDirectory: failOnce.sync
    )

    #expect(throws: OnboardingProgressStoreError.filesystemOperation(
        "sync state directory parent",
        EIO
    )) {
        try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
            rootURL: root,
            directoryName: "Zoid Coach",
            operations: operations,
            unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
            filesystemError: OnboardingProgressStoreError.filesystemOperation
        )
    }
    #expect(!FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Zoid Coach").path
    ))

    let retryRecorder = DescriptorCheckpointRecorder()
    let storage = try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
        rootURL: root,
        directoryName: "Zoid Coach",
        operations: operations,
        checkpoint: retryRecorder.record,
        unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
        filesystemError: OnboardingProgressStoreError.filesystemOperation
    )
    try storage.writeAtomic(Data("durable".utf8), name: "state.json")

    #expect(retryRecorder.values == [
        .createdStateDirectory("Zoid Coach"),
        .syncedStateDirectoryParent("Zoid Coach"),
    ])
    #expect(try storage.read("state.json") == Data("durable".utf8))
}

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
func onboardingMigratesLegacyVersionOneAccessDecisionsAtEveryProgressPoint() throws {
    let cases: [(
        currentStep: OnboardingStep,
        completedSteps: [OnboardingStep],
        coachingMode: InitialCoachingMode?,
        finishedAt: Date?,
        expectedAccess: [OnboardingAccessDecision?]
    )] = [
        (.reminders, [.welcome, .localPrivacy], nil, nil, [nil, nil, nil]),
        (.screenwatch, [.welcome, .localPrivacy, .reminders], nil, nil, [.deferred, nil, nil]),
        (
            .notifications,
            [.welcome, .localPrivacy, .reminders, .screenwatch],
            nil,
            nil,
            [.deferred, .deferred, nil]
        ),
        (
            .applicationInventory,
            Array(OnboardingProgress.stepSequence.prefix(5)),
            nil,
            nil,
            [.deferred, .deferred, .deferred]
        ),
        (
            .firstDailyPlan,
            OnboardingProgress.stepSequence,
            .rulesOnly,
            Date(timeIntervalSinceReferenceDate: 100),
            [.deferred, .deferred, .deferred]
        ),
    ]

    for testCase in cases {
        var object: [String: Any] = [
            "version": 1,
            "currentStep": testCase.currentStep.rawValue,
            "completedSteps": testCase.completedSteps.map(\.rawValue),
        ]
        if let coachingMode = testCase.coachingMode {
            object["coachingMode"] = coachingMode.rawValue
        }
        if let finishedAt = testCase.finishedAt {
            object["finishedAt"] = finishedAt.timeIntervalSinceReferenceDate
        }
        let progress = try JSONDecoder().decode(
            OnboardingProgress.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        try progress.validate()
        #expect(progress.currentStep == testCase.currentStep)
        #expect([
            progress.remindersAccess,
            progress.screenwatchAccess,
            progress.notificationAccess,
        ] == testCase.expectedAccess)
        #expect(progress.finishedAt == testCase.finishedAt)
        #expect(progress.persistenceRevision == 0)
    }
}

@Test
func onboardingLatestRevisionCanCorrectAMigratedCompletedAccessDecision() throws {
    let fixture = try OnboardingStoreFixture(name: "migrated-correction")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let legacy: [String: Any] = [
        "version": 1,
        "currentStep": OnboardingStep.firstDailyPlan.rawValue,
        "completedSteps": OnboardingProgress.stepSequence.map(\.rawValue),
        "coachingMode": InitialCoachingMode.rulesOnly.rawValue,
        "finishedAt": 100.0,
    ]
    try JSONSerialization.data(withJSONObject: legacy).write(to: store.fileURL)
    var migrated = try store.load()
    let stale = migrated
    #expect(migrated.remindersAccess == .deferred)
    #expect(migrated.persistenceRevision == 0)

    try migrated.recordAccessDecision(.granted, for: .reminders)
    migrated = try store.save(migrated)

    #expect(migrated.remindersAccess == .granted)
    #expect(migrated.persistenceRevision == 1)
    #expect(try store.load() == migrated)
    #expect(throws: OnboardingProgressStoreError.staleRevision(expected: 1, actual: 0)) {
        try store.save(stale)
    }
}

@Test
func onboardingRevisionExhaustionFailsWithoutTrappingOrOverwriting() throws {
    let fixture = try OnboardingStoreFixture(name: "revision-exhaustion")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let exhausted = try OnboardingProgress(persistenceRevision: .max)
    try JSONEncoder().encode(exhausted).write(to: store.fileURL)

    #expect(throws: OnboardingProgressStoreError.revisionExhausted) {
        try store.save(exhausted)
    }
    #expect(try store.load() == exhausted)
}

@Test
func onboardingMatchingRevisionCannotReplaceFinishedStateWithWelcome() throws {
    let fixture = try OnboardingStoreFixture(name: "finished-regression")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var finished = try completedOnboardingProgress()
    finished = try store.save(finished)
    let forgedWelcome = try OnboardingProgress(
        persistenceRevision: finished.persistenceRevision
    )

    #expect(throws: OnboardingProgressStoreError.structuralRegression) {
        try store.save(forgedWelcome)
    }
    #expect(try store.load() == finished)
}

@Test
func onboardingMatchingRevisionCannotRegressCompletedPrefix() throws {
    let fixture = try OnboardingStoreFixture(name: "prefix-regression")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var twoSteps = try OnboardingProgress()
    try twoSteps.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
    try twoSteps.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))
    twoSteps = try store.save(twoSteps)
    var oneStep = try OnboardingProgress(
        persistenceRevision: twoSteps.persistenceRevision
    )
    try oneStep.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))

    #expect(throws: OnboardingProgressStoreError.structuralRegression) {
        try store.save(oneStep)
    }
    #expect(try store.load() == twoSteps)
}

@Test
func onboardingDelayedStaleSavesCannotRegressProgressDecisionsOrCompletion() throws {
    let fixture = try OnboardingStoreFixture(name: "stale-save")
    defer { fixture.remove() }
    let staleStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    let forwardStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var oneStep = try OnboardingProgress()
    try oneStep.completeCurrentStep(at: now)
    var twoStepsWithDecision = oneStep
    try twoStepsWithDecision.completeCurrentStep(at: now)
    try twoStepsWithDecision.recordAccessDecision(.denied, for: .reminders)
    twoStepsWithDecision = try forwardStore.save(twoStepsWithDecision)

    #expect(throws: OnboardingProgressStoreError.staleRevision(expected: 1, actual: 0)) {
        try staleStore.save(oneStep)
    }

    #expect(try forwardStore.load() == twoStepsWithDecision)

    var completed = twoStepsWithDecision
    try completed.completeCurrentStep(at: now)
    try completed.recordAccessDecision(.unavailable, for: .screenwatch)
    try completed.completeCurrentStep(at: now)
    try completed.recordAccessDecision(.deferred, for: .notifications)
    for _ in 0 ..< 8 {
        try completed.completeCurrentStep(at: now)
        if completed.currentStep == .coachingMode {
            completed.chooseCoachingMode(.rulesOnly)
        }
    }
    completed = try forwardStore.save(completed)
    #expect(completed.isFinished)

    #expect(throws: OnboardingProgressStoreError.staleRevision(expected: 2, actual: 1)) {
        try staleStore.save(twoStepsWithDecision)
    }

    #expect(try forwardStore.load() == completed)

    var corrected = try forwardStore.load()
    try corrected.recordAccessDecision(.granted, for: .reminders)
    corrected = try forwardStore.save(corrected)
    #expect(corrected.remindersAccess == .granted)
    #expect(corrected.persistenceRevision == 3)
    #expect(try forwardStore.load() == corrected)

    #expect(throws: OnboardingProgressStoreError.staleRevision(expected: 3, actual: 2)) {
        try staleStore.save(completed)
    }

    try forwardStore.reset()

    #expect(try forwardStore.load() == (try OnboardingProgress()))
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
    progress = try firstStore.save(progress)

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
    baseline = try baselineStore.save(baseline)
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
func onboardingRecoveryResumesAfterPreparedInterruption() throws {
    let fixture = try OnboardingStoreFixture(name: "recovery-prepared")
    defer { fixture.remove() }
    let interruptedStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset,
        storageCheckpoint: { checkpoint in
            if checkpoint == .recoveryPrepared { throw OnboardingStoreInterruption.injected }
        }
    )
    try FileManager.default.createDirectory(
        at: interruptedStore.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corruptBytes = Data("prepared-damage".utf8)
    try corruptBytes.write(to: interruptedStore.fileURL)

    #expect(throws: OnboardingStoreInterruption.injected) {
        try interruptedStore.load()
    }
    #expect(try Data(contentsOf: interruptedStore.fileURL) == corruptBytes)
    #expect(FileManager.default.fileExists(atPath: interruptedStore.recoveryFileURL.path))
    #expect(!FileManager.default.fileExists(atPath: interruptedStore.corruptFileURL.path))

    let resumed = try OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset
    ).load()
    #expect(resumed == (try OnboardingProgress()))
    #expect(try Data(contentsOf: interruptedStore.corruptFileURL) == corruptBytes)
    #expect(!FileManager.default.fileExists(atPath: interruptedStore.recoveryFileURL.path))
}

@Test
func onboardingRecoveryResumesAfterReplacementPersistedInterruption() throws {
    let fixture = try OnboardingStoreFixture(name: "recovery-replacement")
    defer { fixture.remove() }
    let interruptedStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        corruptionRecovery: .reset,
        storageCheckpoint: { checkpoint in
            if checkpoint == .replacementStatePersisted {
                throw OnboardingStoreInterruption.injected
            }
        }
    )
    try FileManager.default.createDirectory(
        at: interruptedStore.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corruptBytes = Data("replacement-damage".utf8)
    try corruptBytes.write(to: interruptedStore.fileURL)

    #expect(throws: OnboardingStoreInterruption.injected) {
        try interruptedStore.load()
    }
    #expect(try Data(contentsOf: interruptedStore.corruptFileURL) == corruptBytes)
    #expect(FileManager.default.fileExists(atPath: interruptedStore.recoveryFileURL.path))
    #expect(
        try JSONDecoder().decode(
            OnboardingProgress.self,
            from: Data(contentsOf: interruptedStore.fileURL)
        ) == (try OnboardingProgress())
    )

    let resumed = try OnboardingProgressStore(runtimeEnvironment: fixture.runtime).load()
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

    let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
        for index in 0 ..< 40 {
            let store = index.isMultiple(of: 2) ? first : second
            let progress = index.isMultiple(of: 3) ? welcomeComplete : privacyComplete
            group.addTask {
                do {
                    _ = try store.save(progress)
                    return true
                } catch OnboardingProgressStoreError.staleRevision {
                    return false
                } catch {
                    Issue.record("Unexpected concurrent save error: \(error)")
                    return false
                }
            }
        }
        var values: [Bool] = []
        for await value in group { values.append(value) }
        return values
    }
    #expect(outcomes.filter { $0 }.count == 1)

    var result = try first.load()
    if result.currentStep == .localPrivacy {
        try result.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))
        result = try first.save(result)
    }
    try result.validate()
    #expect(result.currentStep == .reminders)
    #expect(result.completedSteps == [.welcome, .localPrivacy])
}

@Test
func onboardingResetWaitsForAnInFlightSaveAndWinsWhenRequestedAfterIt() async throws {
    let fixture = try OnboardingStoreFixture(name: "save-reset-order")
    defer { fixture.remove() }
    let baselineStore = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    var baseline = try OnboardingProgress()
    try baseline.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
    baseline = try baselineStore.save(baseline)
    var replacement = baseline
    try replacement.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_001))
    let gate = OnboardingCommitGate()
    let savingStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        storageCheckpoint: gate.checkpoint
    )
    let resetAttempt = OnboardingLockAttemptGate(expected: .beforeResetLockAttempt)
    let resetStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        storageCheckpoint: resetAttempt.checkpoint
    )

    let saveTask = Task.detached { try savingStore.save(replacement) }
    #expect(gate.waitUntilSaveReachedCommit())
    let resetCompleted = OnboardingCompletionFlag()
    let resetTask = Task.detached {
        try resetStore.reset()
        resetCompleted.markCompleted()
    }
    #expect(resetAttempt.waitUntilAttempted())
    #expect(!resetCompleted.isCompleted)
    gate.allowCommit()
    _ = try await saveTask.value
    try await resetTask.value

    #expect(try baselineStore.load() == (try OnboardingProgress()))
}

@Test
func onboardingStoreWaitsForAChildProcessAdvisoryLock() async throws {
    let fixture = try OnboardingStoreFixture(name: "child-lock")
    defer { fixture.remove() }
    let store = OnboardingProgressStore(runtimeEnvironment: fixture.runtime)
    let persisted = try store.save(try OnboardingProgress())
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
    let saveAttempt = OnboardingLockAttemptGate(expected: .beforeSaveLockAttempt)
    let blockedStore = OnboardingProgressStore(
        runtimeEnvironment: fixture.runtime,
        storageCheckpoint: saveAttempt.checkpoint
    )
    let saveTask = Task.detached {
        var progress = persisted
        try progress.completeCurrentStep(at: Date(timeIntervalSince1970: 1_800_000_000))
        _ = try blockedStore.save(progress)
        completion.markCompleted()
    }
    #expect(saveAttempt.waitUntilAttempted())
    #expect(!completion.isCompleted)
    try Data("release".utf8).write(to: release)
    child.waitUntilExit()
    _ = try await saveTask.value
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
    _ = OnboardingProgressStore(runtimeEnvironment: qa, fileManager: .default)

    #expect(productionStore.fileURL.path == productionSupport.path + "/Zoid Coach/onboarding-progress.json")
    #expect(qaStore.fileURL.path == qaRoot.path + "/Application Support/Zoid Coach/onboarding-progress.json")
    #expect(productionStore.fileURL != qaStore.fileURL)
    try qaStore.save(try OnboardingProgress())
    #expect(!FileManager.default.fileExists(atPath: productionStore.fileURL.path))
}

private enum OnboardingStoreInterruption: Error, Equatable {
    case injected
}

private func completedOnboardingProgress() throws -> OnboardingProgress {
    try OnboardingProgress(
        currentStep: .firstDailyPlan,
        completedSteps: OnboardingProgress.stepSequence,
        coachingMode: .rulesOnly,
        remindersAccess: .denied,
        screenwatchAccess: .unavailable,
        notificationAccess: .deferred,
        finishedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private func writeDownstreamPackage(
    at packageRoot: URL,
    repositoryRoot: URL,
    targets: [(name: String, product: String, source: String)]
) throws {
    let targetDeclarations = targets.map { target in
        """
        .executableTarget(
            name: "\(target.name)",
            dependencies: [.product(name: "\(target.product)", package: "ZoidCoach")]
        )
        """
    }.joined(separator: ",\n")
    let manifest = """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: "OnboardingPersistenceConsumer",
        platforms: [.macOS(.v14)],
        dependencies: [.package(name: "ZoidCoach", path: "\(repositoryRoot.path)")],
        targets: [
    \(targetDeclarations)
        ]
    )
    """
    try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
    try manifest.write(
        to: packageRoot.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
    for target in targets {
        let sourceDirectory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(target.name, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try target.source.write(
            to: sourceDirectory.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private func runDownstreamBuild(at packageRoot: URL) throws -> (
    status: Int32,
    errorOutput: String
) {
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "build", "--package-path", packageRoot.path]
    process.standardOutput = errorPipe
    process.standardError = errorPipe
    try process.run()
    let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: errorData, as: UTF8.self))
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

private final class OnboardingLockAttemptGate: @unchecked Sendable {
    private let expected: OnboardingPersistenceCheckpoint
    private let attempted = DispatchSemaphore(value: 0)

    init(expected: OnboardingPersistenceCheckpoint) {
        self.expected = expected
    }

    func checkpoint(_ checkpoint: OnboardingPersistenceCheckpoint) {
        if checkpoint == expected { attempted.signal() }
    }

    func waitUntilAttempted() -> Bool {
        attempted.wait(timeout: .now() + 5) == .success
    }
}

private final class DescriptorCheckpointRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DescriptorRelativeStateDirectoryCheckpoint] = []

    func record(_ checkpoint: DescriptorRelativeStateDirectoryCheckpoint) {
        lock.withLock { recorded.append(checkpoint) }
    }

    var values: [DescriptorRelativeStateDirectoryCheckpoint] {
        lock.withLock { recorded }
    }
}

private final class DescriptorFailOnceSync: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true

    func sync(_ descriptor: Int32) -> Int32 {
        let failure = lock.withLock {
            defer { shouldFail = false }
            return shouldFail
        }
        return failure
            ? EIO
            : DescriptorRelativeStateDirectoryOperations.live.syncDirectory(descriptor)
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
