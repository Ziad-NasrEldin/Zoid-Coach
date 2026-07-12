import Testing
@testable import ZoidCoachApp

struct QAAgentRegistrationLifecycleTests {
    @Test
    func firstInstallRegistersAnUnregisteredAgent() throws {
        let service = LifecycleRegistration(status: .notRegistered)

        try QAAgentRegistrationLifecycle.install(service: service)

        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
        #expect(service.status == .enabled)
    }

    @Test
    func repeatInstallReplacesAnEnabledRegistration() throws {
        let service = LifecycleRegistration(status: .enabled)

        try QAAgentRegistrationLifecycle.install(service: service)

        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 1)
        #expect(service.status == .enabled)
    }

    @Test
    func staleEnabledRegistrationIsPolledBeforeRegisteringReplacement() throws {
        let service = LifecycleRegistration(
            status: .enabled,
            unregisterStatusReads: [.enabled, .enabled, .notRegistered]
        )

        try QAAgentRegistrationLifecycle.install(service: service)

        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 1)
        #expect(service.status == .enabled)
    }

    @Test
    func interruptedRegistrationRetriesFromAReconciledState() throws {
        let service = LifecycleRegistration(status: .notRegistered, failedRegisterAttempts: 1)

        try QAAgentRegistrationLifecycle.install(service: service)

        #expect(service.registerCount == 2)
        #expect(service.status == .enabled)
    }

    @Test
    func uninstallAndReinstallAreBothIdempotent() throws {
        let service = LifecycleRegistration(status: .enabled)

        try QAAgentRegistrationLifecycle.uninstall(service: service)
        try QAAgentRegistrationLifecycle.uninstall(service: service)
        try QAAgentRegistrationLifecycle.install(service: service)

        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 1)
        #expect(service.status == .enabled)
    }
}

private final class LifecycleRegistration: QAAgentServiceRegistration {
    private var currentStatus: AgentRegistrationStatus
    private var unregisterStatusReads: [AgentRegistrationStatus]
    private var failedRegisterAttempts: Int
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(
        status: AgentRegistrationStatus,
        unregisterStatusReads: [AgentRegistrationStatus] = [],
        failedRegisterAttempts: Int = 0
    ) {
        currentStatus = status
        self.unregisterStatusReads = unregisterStatusReads
        self.failedRegisterAttempts = failedRegisterAttempts
    }

    var status: AgentRegistrationStatus {
        if !unregisterStatusReads.isEmpty {
            let status = unregisterStatusReads.removeFirst()
            currentStatus = status
        }
        return currentStatus
    }

    func register() throws {
        registerCount += 1
        if failedRegisterAttempts > 0 {
            failedRegisterAttempts -= 1
            throw LifecycleTestError.interrupted
        }
        currentStatus = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if unregisterStatusReads.isEmpty {
            currentStatus = .notRegistered
        }
    }
}

private enum LifecycleTestError: Error {
    case interrupted
}
