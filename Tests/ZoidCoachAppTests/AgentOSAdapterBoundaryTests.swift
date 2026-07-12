import Foundation
import Testing
import ZoidCoachCore

@Test
func qaAgentRejectsEveryProductionOSAdapterOperation() throws {
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-agent-os-boundary-\(UUID().uuidString)"],
        processEnvironment: [:]
    ).environment

    for operation in AgentOSAdapterOperation.allCases {
        #expect(throws: AgentOSAdapterBoundaryError.self) {
            try AgentOSAdapterBoundary.validate(
                runtimeEnvironment: runtimeEnvironment,
                operations: [operation]
            )
        }
    }
}

@Test
func qaAgentFlagsMapToFailClosedOSOperations() {
    #expect(
        AgentOSAdapterBoundary.operations(
            requestRemindersAccess: true,
            printRemindersStatus: false
        ) == [.requestRemindersAccess]
    )
    #expect(
        AgentOSAdapterBoundary.operations(
            requestRemindersAccess: false,
            printRemindersStatus: true
        ) == [.inspectRemindersAccess]
    )
    #expect(
        AgentOSAdapterBoundary.operations(
            requestRemindersAccess: false,
            printRemindersStatus: false
        ) == [.synchronizeReminders, .synchronizeCalendar, .deliverNotifications]
    )
}

@Test
func productionAgentAllowsExistingOSAdapterOperations() {
    #expect(throws: Never.self) {
        try AgentOSAdapterBoundary.validate(
            runtimeEnvironment: .production(),
            operations: Set(AgentOSAdapterOperation.allCases)
        )
    }
}
