import Foundation
import ZoidCoachCore

public enum RuntimePermissionHealth: String, Codable, Equatable, Sendable {
    case granted
    case denied
    case notRequired = "not_required"
    case unknown
}

public struct NativeCaptureConfiguration: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case legacy
        case parity
        case native
    }

    public let mode: Mode
    public let configuredDisplayIDs: [UInt32]
    public let parityPassed: Bool

    public init(mode: Mode = .legacy, configuredDisplayIDs: [UInt32] = [], parityPassed: Bool = false) {
        self.mode = mode == .native && !parityPassed ? .parity : mode
        self.configuredDisplayIDs = Array(Set(configuredDisplayIDs)).sorted()
        self.parityPassed = parityPassed
    }

    public static let legacy = NativeCaptureConfiguration()

    public init(policy: CapturePolicy, parityPassed: Bool = false) {
        let requestedMode = Mode(rawValue: policy.mode.rawValue) ?? .legacy
        self.init(mode: requestedMode, configuredDisplayIDs: policy.configuredDisplayIDs, parityPassed: parityPassed)
    }

    public var policy: CapturePolicy {
        CapturePolicy(mode: CaptureMode(rawValue: mode.rawValue) ?? .legacy, configuredDisplayIDs: configuredDisplayIDs)
    }
}

public final class NativeCaptureConfigurationStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL = NativeCaptureConfigurationStore.defaultURL(runtimeEnvironment: .current())) {
        self.fileURL = fileURL
    }

    public func load() throws -> NativeCaptureConfiguration {
        try lock.withLock {
            let storage = try makeStorage()
            return try storage.withLock(exclusive: false) {
                guard try storage.exists(fileURL.lastPathComponent) else { return .legacy }
                return try JSONDecoder().decode(
                    NativeCaptureConfiguration.self,
                    from: storage.read(fileURL.lastPathComponent)
                )
            }
        }
    }

    public func save(_ configuration: NativeCaptureConfiguration) throws {
        try lock.withLock {
            let storage = try makeStorage()
            let data = try JSONEncoder().encode(configuration)
            try storage.withLock(exclusive: true) {
                try storage.writeAtomic(data, name: fileURL.lastPathComponent)
            }
        }
    }

    private func makeStorage() throws -> DescriptorRelativeStateDirectory<NativeCaptureConfigurationStoreError> {
        let directoryURL = fileURL.deletingLastPathComponent()
        return try DescriptorRelativeStateDirectory(
            rootURL: directoryURL.deletingLastPathComponent(),
            directoryName: directoryURL.lastPathComponent,
            createRootIfMissing: true,
            unsafeEntryError: NativeCaptureConfigurationStoreError.unsafeFilesystemEntry,
            filesystemError: NativeCaptureConfigurationStoreError.filesystemOperation
        )
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ZoidCoachStorage.productSupportURL(
            applicationSupportRoot: support,
            fileManager: fileManager
        ).appendingPathComponent("native-capture-config.json", isDirectory: false)
    }

    public static func defaultURL(runtimeEnvironment: RuntimeEnvironment) -> URL {
        runtimeEnvironment.nativeCaptureConfigurationURL
    }
}

public enum NativeCaptureConfigurationStoreError: LocalizedError, Equatable, Sendable {
    case unsafeFilesystemEntry(String)
    case filesystemOperation(String, Int32)

    public var errorDescription: String? {
        switch self {
        case let .unsafeFilesystemEntry(path):
            "Capture configuration storage rejected the unsafe entry '\(path)'."
        case let .filesystemOperation(operation, code):
            "Capture configuration storage could not \(operation) (errno \(code))."
        }
    }
}

public struct AgentCaptureHealthSnapshot: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let isRunning: Bool
    public let screenRecording: RuntimePermissionHealth
    public let accessibility: RuntimePermissionHealth
    public let automation: RuntimePermissionHealth
    public let configuredDisplayIDs: [UInt32]
    public let lastCaptureAt: Date?
    public let detail: String

    public init(
        isEnabled: Bool,
        isRunning: Bool,
        screenRecording: RuntimePermissionHealth,
        accessibility: RuntimePermissionHealth,
        automation: RuntimePermissionHealth,
        configuredDisplayIDs: [UInt32] = [],
        lastCaptureAt: Date? = nil,
        detail: String
    ) {
        self.isEnabled = isEnabled
        self.isRunning = isRunning
        self.screenRecording = screenRecording
        self.accessibility = accessibility
        self.automation = automation
        self.configuredDisplayIDs = configuredDisplayIDs
        self.lastCaptureAt = lastCaptureAt
        self.detail = detail
    }
}

public final class AgentCaptureHealthStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AgentCaptureHealthSnapshot

    public init(initial: AgentCaptureHealthSnapshot) { stored = initial }

    public var snapshot: AgentCaptureHealthSnapshot { lock.withLock { stored } }

    public func update(_ value: AgentCaptureHealthSnapshot) {
        lock.withLock { stored = value }
    }
}

public enum NativeCapturePolicy {
    public static let metadataCadenceSeconds: TimeInterval = 5
    public static let idleSkipSeconds: TimeInterval = 90

    public static func shouldCaptureImage(idleSeconds: TimeInterval, idleSkipSeconds: TimeInterval = idleSkipSeconds) -> Bool {
        idleSeconds < idleSkipSeconds
    }

    public static func selectedDisplayIDs(available: [UInt32], configured: Set<UInt32>) -> [UInt32] {
        available.filter { configured.isEmpty || configured.contains($0) }
    }

    public static func appOwnedDaysDirectory(applicationSupportDirectory: URL) -> URL {
        ZoidCoachStorage.productSupportURL(applicationSupportRoot: applicationSupportDirectory)
            .appendingPathComponent("native-capture/days", isDirectory: true)
    }

    public static func pathsDoNotCollide(native: URL, legacy: URL) -> Bool {
        native.standardizedFileURL != legacy.standardizedFileURL
    }
}
