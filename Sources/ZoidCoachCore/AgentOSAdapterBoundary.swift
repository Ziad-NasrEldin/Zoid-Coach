import Foundation

public enum AgentOSAdapterOperation: String, CaseIterable, Equatable, Sendable {
    case requestRemindersAccess
    case inspectRemindersAccess
    case synchronizeReminders
    case synchronizeCalendar
    case deliverNotifications
}

public struct AgentOSFixtureAuthorization: @unchecked Sendable {
    package let authorizes: @Sendable (RuntimeEnvironment) -> Bool

    package init(authorizes: @escaping @Sendable (RuntimeEnvironment) -> Bool) {
        self.authorizes = authorizes
    }
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
        if fixtureAuthorization?.authorizes(runtimeEnvironment) == true {
            return
        }
        throw AgentOSAdapterBoundaryError.isolatedAdaptersRequired(
            operations: operations.map(\.rawValue).sorted()
        )
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
