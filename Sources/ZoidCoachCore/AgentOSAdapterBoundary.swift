import Foundation

public enum AgentOSAdapterOperation: String, CaseIterable, Equatable, Sendable {
    case requestRemindersAccess
    case inspectRemindersAccess
    case synchronizeReminders
    case synchronizeCalendar
    case deliverNotifications
}

public struct AgentOSFixtureAuthorization: Equatable, Sendable {
    fileprivate let runRoot: URL
}

public enum AgentOSAdapterBoundary {
    public static func operations(
        requestRemindersAccess: Bool,
        printRemindersStatus: Bool
    ) -> Set<AgentOSAdapterOperation> {
        if requestRemindersAccess { return [.requestRemindersAccess] }
        if printRemindersStatus { return [.inspectRemindersAccess] }
        return [.synchronizeReminders, .synchronizeCalendar, .deliverNotifications]
    }

    public static func validate(
        runtimeEnvironment: RuntimeEnvironment,
        operations: Set<AgentOSAdapterOperation>,
        fixtureAuthorization: AgentOSFixtureAuthorization? = nil
    ) throws {
        guard case .qa = runtimeEnvironment.mode, !operations.isEmpty else { return }
        if case let .qa(runRoot) = runtimeEnvironment.mode,
           fixtureAuthorization?.runRoot == runRoot {
            return
        }
        throw AgentOSAdapterBoundaryError.isolatedAdaptersRequired(
            operations: operations.map(\.rawValue).sorted()
        )
    }

    public static func authorizeFixture(
        runtimeEnvironment: RuntimeEnvironment
    ) throws -> AgentOSFixtureAuthorization {
        guard case let .qa(runRoot) = runtimeEnvironment.mode,
              runtimeEnvironment.packageMode == .qa,
              runtimeEnvironment.identity == .qa else {
            throw AgentOSAdapterBoundaryError.isolatedAdaptersRequired(
                operations: AgentOSAdapterOperation.allCases.map(\.rawValue).sorted()
            )
        }
        return AgentOSFixtureAuthorization(runRoot: runRoot)
    }
}

public enum AgentOSAdapterBoundaryError: LocalizedError, Equatable {
    case isolatedAdaptersRequired(operations: [String])

    public var errorDescription: String? {
        switch self {
        case let .isolatedAdaptersRequired(operations):
            "QA agent refused production OS adapters: \(operations.joined(separator: ", "))"
        }
    }
}
