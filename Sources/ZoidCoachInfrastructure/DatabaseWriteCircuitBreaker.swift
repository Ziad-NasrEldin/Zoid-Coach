import Foundation

public struct AgentRuntimeSafetySnapshot: Codable, Equatable, Sendable {
    public let isTripped: Bool
    public let trippedAt: Date?
    public let reason: String?

    public init(isTripped: Bool, trippedAt: Date? = nil, reason: String? = nil) {
        self.isTripped = isTripped
        self.trippedAt = trippedAt
        self.reason = reason
    }

    public var isReadOnly: Bool { isTripped }

    public static let writable = AgentRuntimeSafetySnapshot(isTripped: false)
}

public final class DatabaseWriteCircuitBreaker: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = AgentRuntimeSafetySnapshot.writable

    public init() {}

    public var snapshot: AgentRuntimeSafetySnapshot {
        lock.withLock { stored }
    }

    public var allowsExternalMutations: Bool { !snapshot.isTripped }

    public func trip(reason: String, at date: Date = Date()) {
        lock.withLock {
            guard !stored.isTripped else { return }
            stored = AgentRuntimeSafetySnapshot(
                isTripped: true,
                trippedAt: date,
                reason: Self.redactedReason(reason)
            )
        }
    }

    public func reset() {
        lock.withLock { stored = .writable }
    }

    public func throwIfTripped() throws {
        let current = snapshot
        guard !current.isTripped else {
            throw DatabaseWriteCircuitBreakerError.readOnly(current.reason ?? "Database writes are unavailable.")
        }
    }

    private static func redactedReason(_ reason: String) -> String {
        let singleLine = reason.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(240))
    }
}

public enum DatabaseWriteCircuitBreakerError: LocalizedError, Equatable {
    case readOnly(String)

    public var errorDescription: String? {
        switch self {
        case let .readOnly(reason):
            return "Zoid Coach is read-only because a database write failed. External actions are blocked. \(reason)"
        }
    }
}
