import Foundation
import ZoidCoachCore

public enum OnboardingCorruptionRecovery: Equatable, Sendable {
    case fail
    case reset
}

public enum OnboardingPersistenceCheckpoint: Equatable, Sendable {
    case beforeStateCommit
    case recoveryPrepared
    case corruptStateQuarantined
    case replacementStatePersisted
}

public enum OnboardingProgressStoreError: LocalizedError, Equatable, Sendable {
    case corruptProgress(path: String)
    case unsafeFilesystemEntry(String)
    case filesystemOperation(String, Int32)

    public var errorDescription: String? {
        switch self {
        case let .corruptProgress(path):
            "Onboarding progress is corrupt: \(path)"
        case let .unsafeFilesystemEntry(name):
            "Onboarding persistence refused an unsafe filesystem entry: \(name)"
        case let .filesystemOperation(operation, code):
            "Onboarding persistence could not \(operation), errno \(code)"
        }
    }
}

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

    public let fileURL: URL
    public let corruptFileURL: URL
    public let recoveryFileURL: URL

    public init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        corruptionRecovery: OnboardingCorruptionRecovery = .fail,
        storageCheckpoint: @escaping @Sendable (OnboardingPersistenceCheckpoint) throws -> Void = { _ in }
    ) {
        applicationSupportRoot = runtimeEnvironment.applicationSupportRoot.standardizedFileURL
        self.corruptionRecovery = corruptionRecovery
        self.storageCheckpoint = storageCheckpoint
        let directory = applicationSupportRoot.appendingPathComponent(Self.directoryName, isDirectory: true)
        fileURL = directory.appendingPathComponent(Self.stateName, isDirectory: false)
        corruptFileURL = directory.appendingPathComponent(Self.corruptStateName, isDirectory: false)
        recoveryFileURL = directory.appendingPathComponent(Self.recoveryName, isDirectory: false)
    }

    public func load() throws -> OnboardingProgress {
        try withStorage { storage in
            try storage.withLock(exclusive: true) {
                if try storage.exists(Self.recoveryName) {
                    let transaction = try decode(
                        RecoveryTransaction.self,
                        from: storage.read(Self.recoveryName),
                        path: recoveryFileURL.path
                    )
                    return try resumeRecovery(transaction, storage: storage)
                }
                guard try storage.exists(Self.stateName) else {
                    return try OnboardingProgress()
                }
                do {
                    let progress = try JSONDecoder().decode(
                        OnboardingProgress.self,
                        from: storage.read(Self.stateName)
                    )
                    try progress.validate()
                    return progress
                } catch let error as OnboardingProgressStoreError {
                    throw error
                } catch {
                    return try recoverCorruptProgress(storage: storage)
                }
            }
        }
    }

    public func save(_ progress: OnboardingProgress) throws {
        try progress.validate()
        try withStorage { storage in
            try storage.withLock(exclusive: true) {
                try persist(progress, storage: storage)
            }
        }
    }

    public func reset() throws {
        try withStorage { storage in
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
