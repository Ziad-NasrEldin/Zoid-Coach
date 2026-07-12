import Foundation
@_spi(OnboardingPersistence) import ZoidCoachCore

public enum OnboardingCorruptionRecovery: Equatable, Sendable {
    case fail
    case reset
}

public enum OnboardingPersistenceCheckpoint: Equatable, Sendable {
    case beforeLoadLockAttempt
    case beforeSaveLockAttempt
    case beforeResetLockAttempt
    case beforeStateCommit
    case recoveryPrepared
    case corruptStateQuarantined
    case replacementStatePersisted
}

public enum OnboardingProgressStoreError: LocalizedError, Equatable, Sendable {
    case corruptProgress(path: String)
    case unsafeFilesystemEntry(String)
    case filesystemOperation(String, Int32)
    case staleRevision(expected: UInt64, actual: UInt64)
    case revisionExhausted
    case structuralRegression
    case missingDurableEffect(OnboardingStep)
    case unexpectedDurableEffect(OnboardingStep)
    case durableEffectRegression(OnboardingStep)
    case unverifiedDurableEffect(OnboardingStep)

    public var errorDescription: String? {
        switch self {
        case let .corruptProgress(path):
            "Onboarding progress is corrupt: \(path)"
        case let .unsafeFilesystemEntry(name):
            "Onboarding persistence refused an unsafe filesystem entry: \(name)"
        case let .filesystemOperation(operation, code):
            "Onboarding persistence could not \(operation), errno \(code)"
        case let .staleRevision(expected, actual):
            "Onboarding progress revision is stale: expected \(expected), received \(actual)"
        case .revisionExhausted:
            "Onboarding progress revision cannot advance beyond UInt64.max"
        case .structuralRegression:
            "Onboarding progress cannot move backward without an explicit reset"
        case let .missingDurableEffect(step):
            "Onboarding cannot complete \(step.rawValue) before its side effect is durable"
        case let .unexpectedDurableEffect(step):
            "Onboarding cannot record a durable effect without completing \(step.rawValue)"
        case let .durableEffectRegression(step):
            "Onboarding cannot replace or remove the durable effect for \(step.rawValue)"
        case let .unverifiedDurableEffect(step):
            "Onboarding could not verify the durable policy receipt for \(step.rawValue)"
        }
    }
}

/// Durable onboarding persistence exported by the `ZoidCoachInfrastructure` library product.
/// The module is also bundled in the existing `ZoidCoachCore` product for dependency compatibility.
///
/// The `fileManager` initializer argument remains source-compatible with the former Core store.
/// Persistence intentionally uses descriptor-relative system calls instead of `FileManager`.
public final class OnboardingProgressStore: @unchecked Sendable {
    private static let directoryName = "Zoid Coach"
    private static let stateName = "onboarding-progress.json"
    private static let corruptStateName = "onboarding-progress.corrupt.json"
    private static let recoveryName = "onboarding-progress.recovery.json"

    private enum RecoveryPhase: String, Codable, Sendable {
        case prepared
        case quarantined
        case replacementWritten
    }

    private struct RecoveryTransaction: Codable, Sendable {
        var phase: RecoveryPhase
        let replacement: OnboardingProgress
    }

    private let applicationSupportRoot: URL
    private let corruptionRecovery: OnboardingCorruptionRecovery
    private let storageCheckpoint: @Sendable (OnboardingPersistenceCheckpoint) throws -> Void
    private let durableEffectValidator: @Sendable (
        OnboardingCompletedEffect,
        OnboardingProgress
    ) throws -> Bool

    public let fileURL: URL
    public let corruptFileURL: URL
    public let recoveryFileURL: URL

    public init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        fileManager _: FileManager = .default,
        corruptionRecovery: OnboardingCorruptionRecovery = .fail,
        storageCheckpoint: @escaping @Sendable (OnboardingPersistenceCheckpoint) throws -> Void = { _ in },
        durableEffectValidator: (@Sendable (
            OnboardingCompletedEffect,
            OnboardingProgress
        ) throws -> Bool)? = nil
    ) {
        applicationSupportRoot = runtimeEnvironment.applicationSupportRoot.standardizedFileURL
        self.corruptionRecovery = corruptionRecovery
        self.storageCheckpoint = storageCheckpoint
        if let durableEffectValidator {
            self.durableEffectValidator = durableEffectValidator
        } else {
            let databaseURL = runtimeEnvironment.databaseURL
            self.durableEffectValidator = { effect, progress in
                let policyStore = try PolicyStore(databaseURL: databaseURL, readOnly: true)
                guard let receipt = try policyStore.mutationReceipt(requestID: effect.requestID),
                      receipt.payloadDigest == effect.payloadDigest,
                      receipt.resultingVersion == effect.resourceVersion,
                      case let .onboarding(flowID, step, progressRevision) = receipt.origin,
                      flowID == progress.flowID,
                      step == effect.step,
                      progressRevision == progress.persistenceRevision else {
                    return false
                }
                return true
            }
        }
        let directory = applicationSupportRoot.appendingPathComponent(Self.directoryName, isDirectory: true)
        fileURL = directory.appendingPathComponent(Self.stateName, isDirectory: false)
        corruptFileURL = directory.appendingPathComponent(Self.corruptStateName, isDirectory: false)
        recoveryFileURL = directory.appendingPathComponent(Self.recoveryName, isDirectory: false)
    }

    public func load() throws -> OnboardingProgress {
        try withStorage { storage in
            try storageCheckpoint(.beforeLoadLockAttempt)
            return try storage.withLock(exclusive: true) {
                try loadLocked(storage: storage).progress
            }
        }
    }

    @discardableResult
    public func save(_ progress: OnboardingProgress) throws -> OnboardingProgress {
        try progress.validate()
        return try withStorage { storage in
            try storageCheckpoint(.beforeSaveLockAttempt)
            return try storage.withLock(exclusive: true) {
                let stored = try loadLocked(storage: storage)
                let expectedRevision = stored.isPersisted
                    ? stored.progress.persistenceRevision
                    : 0
                guard progress.persistenceRevision == expectedRevision else {
                    throw OnboardingProgressStoreError.staleRevision(
                        expected: expectedRevision,
                        actual: progress.persistenceRevision
                    )
                }
                if stored.isPersisted {
                    try validateStructuralMonotonicity(
                        current: stored.progress,
                        incoming: progress
                    )
                }
                try validateDurableEffects(
                    current: stored.isPersisted ? stored.progress : nil,
                    incoming: progress
                )
                guard expectedRevision < UInt64.max else {
                    throw OnboardingProgressStoreError.revisionExhausted
                }
                let replacement = try progress.withPersistenceRevision(expectedRevision + 1)
                try persist(replacement, storage: storage)
                return replacement
            }
        }
    }

    public func reset() throws {
        try withStorage { storage in
            try storageCheckpoint(.beforeResetLockAttempt)
            try storage.withLock(exclusive: true) {
                if try storage.exists(Self.recoveryName) {
                    let transaction = try decode(
                        RecoveryTransaction.self,
                        from: storage.read(Self.recoveryName),
                        path: recoveryFileURL.path
                    )
                    _ = try resumeRecovery(transaction, storage: storage)
                }
                try storage.removeIfPresent(Self.stateName)
            }
        }
    }

    private func withStorage<T>(
        _ body: (DescriptorRelativeStateDirectory<OnboardingProgressStoreError>) throws -> T
    ) throws -> T {
        let storage = try DescriptorRelativeStateDirectory<OnboardingProgressStoreError>(
            rootURL: applicationSupportRoot,
            directoryName: Self.directoryName,
            createRootIfMissing: true,
            unsafeEntryError: OnboardingProgressStoreError.unsafeFilesystemEntry,
            filesystemError: OnboardingProgressStoreError.filesystemOperation
        )
        return try body(storage)
    }

    private func loadLocked(
        storage: DescriptorRelativeStateDirectory<OnboardingProgressStoreError>
    ) throws -> (progress: OnboardingProgress, isPersisted: Bool) {
        if try storage.exists(Self.recoveryName) {
            let transaction = try decode(
                RecoveryTransaction.self,
                from: storage.read(Self.recoveryName),
                path: recoveryFileURL.path
            )
            return (try resumeRecovery(transaction, storage: storage), true)
        }
        guard try storage.exists(Self.stateName) else {
            let fresh = try OnboardingProgress()
            try persist(fresh, storage: storage)
            return (fresh, true)
        }
        do {
            let progress = try JSONDecoder().decode(
                OnboardingProgress.self,
                from: storage.read(Self.stateName)
            )
            try progress.validate()
            return (progress, true)
        } catch let error as OnboardingProgressStoreError {
            throw error
        } catch {
            return (try recoverCorruptProgress(storage: storage), true)
        }
    }

    private func validateStructuralMonotonicity(
        current: OnboardingProgress,
        incoming: OnboardingProgress
    ) throws {
        guard incoming.completedSteps.starts(with: current.completedSteps),
              let currentStepIndex = OnboardingProgress.stepSequence.firstIndex(
                of: current.currentStep
              ),
              let incomingStepIndex = OnboardingProgress.stepSequence.firstIndex(
                of: incoming.currentStep
              ),
              incomingStepIndex >= currentStepIndex,
              current.finishedAt == nil || incoming.finishedAt == current.finishedAt else {
            throw OnboardingProgressStoreError.structuralRegression
        }
        if incoming.completedSteps == current.completedSteps {
            guard incoming.currentStep == current.currentStep,
                  incoming.coachingMode == current.coachingMode,
                  incoming.finishedAt == current.finishedAt else {
                throw OnboardingProgressStoreError.structuralRegression
            }
        }
    }

    private func validateDurableEffects(
        current: OnboardingProgress?,
        incoming: OnboardingProgress
    ) throws {
        let currentCompleted = Set(current?.completedSteps ?? [])
        let newlyCompleted = Set(incoming.completedSteps).subtracting(currentCompleted)
        let currentEffects = Dictionary(
            uniqueKeysWithValues: (current?.completedEffects ?? []).map { ($0.step, $0) }
        )
        let incomingEffects = Dictionary(
            uniqueKeysWithValues: incoming.completedEffects.map { ($0.step, $0) }
        )
        for (step, effect) in currentEffects where incomingEffects[step] != effect {
            throw OnboardingProgressStoreError.durableEffectRegression(step)
        }
        for step in Self.effectRequiredSteps where newlyCompleted.contains(step) {
            guard let effect = incomingEffects[step] else {
                throw OnboardingProgressStoreError.missingDurableEffect(step)
            }
            guard try durableEffectValidator(effect, incoming) else {
                throw OnboardingProgressStoreError.unverifiedDurableEffect(step)
            }
        }
        for step in incomingEffects.keys where currentEffects[step] == nil
            && !newlyCompleted.contains(step) {
            throw OnboardingProgressStoreError.unexpectedDurableEffect(step)
        }
    }

    private static let effectRequiredSteps: Set<OnboardingStep> = [
        .activityClassification,
        .schedule,
        .gamingPolicy,
        .coachingMode,
    ]

    private func recoverCorruptProgress(
        storage: DescriptorRelativeStateDirectory<OnboardingProgressStoreError>
    ) throws -> OnboardingProgress {
        guard corruptionRecovery == .reset else {
            throw OnboardingProgressStoreError.corruptProgress(path: fileURL.path)
        }
        let replacement = try OnboardingProgress()
        let transaction = RecoveryTransaction(phase: .prepared, replacement: replacement)
        try storage.writeAtomic(try encode(transaction), name: Self.recoveryName)
        try storageCheckpoint(.recoveryPrepared)
        return try resumeRecovery(transaction, storage: storage)
    }

    private func resumeRecovery(
        _ initial: RecoveryTransaction,
        storage: DescriptorRelativeStateDirectory<OnboardingProgressStoreError>
    ) throws -> OnboardingProgress {
        var transaction = initial
        try transaction.replacement.validate()
        if transaction.phase == .prepared {
            if try storage.exists(Self.stateName) {
                try storage.rename(Self.stateName, to: Self.corruptStateName)
            }
            transaction.phase = .quarantined
            try storage.writeAtomic(try encode(transaction), name: Self.recoveryName)
            try storageCheckpoint(.corruptStateQuarantined)
        }
        if transaction.phase == .quarantined {
            try persist(transaction.replacement, storage: storage)
            transaction.phase = .replacementWritten
            try storage.writeAtomic(try encode(transaction), name: Self.recoveryName)
            try storageCheckpoint(.replacementStatePersisted)
        }
        try storage.removeIfPresent(Self.recoveryName)
        return transaction.replacement
    }

    private func persist(
        _ progress: OnboardingProgress,
        storage: DescriptorRelativeStateDirectory<OnboardingProgressStoreError>
    ) throws {
        try storage.writeAtomic(try encode(progress), name: Self.stateName) {
            try storageCheckpoint(.beforeStateCommit)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OnboardingProgressStoreError.corruptProgress(path: path)
        }
    }
}
