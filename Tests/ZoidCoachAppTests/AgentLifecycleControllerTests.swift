import Foundation
import Testing
@testable import ZoidCoachApp

@MainActor
@Test
func agentLifecycleControllerExposesApprovalRecoveryAndReturnsHealthy() {
    let service = StubAgentLifecycleService(
        inspected: agentHealth(.attention, detail: "Approval required"),
        enabled: agentHealth(.healthy, detail: "Agent is running"),
        disabled: agentHealth(.notConnected, detail: "Agent is disabled")
    )
    let controller = AgentLifecycleController(
        service: service,
        now: { Date(timeIntervalSince1970: 123) },
        openURL: { _ in true }
    )

    #expect(controller.health.state == .attention)
    #expect(!controller.canEnable)
    #expect(controller.canRepair)
    #expect(!controller.canDisable)

    controller.repair()

    #expect(service.enableCalls == 1)
    #expect(controller.health.state == .healthy)
    #expect(controller.health.detail == "Agent is running")
    #expect(controller.canDisable)
    #expect(controller.operation == .idle)
    #expect(controller.lastCheckedAt == Date(timeIntervalSince1970: 123))
}

@MainActor
@Test
func agentLifecycleControllerDisablesWithoutDeletingForegroundState() {
    let service = StubAgentLifecycleService(
        inspected: agentHealth(.healthy, detail: "Agent is running"),
        enabled: agentHealth(.healthy, detail: "Agent is running"),
        disabled: agentHealth(.notConnected, detail: "Background work is disabled")
    )
    let controller = AgentLifecycleController(service: service)

    controller.disable()

    #expect(service.disableCalls == 1)
    #expect(controller.health.state == .notConnected)
    #expect(controller.health.detail == "Background work is disabled")
    #expect(controller.canEnable)
    #expect(!controller.canRepair)
    #expect(!controller.canDisable)
}

@MainActor
@Test
func agentLifecycleControllerRefreshesARecoveredProcess() {
    let service = StubAgentLifecycleService(
        inspected: agentHealth(.attention, detail: "Agent stopped"),
        enabled: agentHealth(.healthy, detail: "Agent is running"),
        disabled: agentHealth(.notConnected, detail: "Agent is disabled")
    )
    let controller = AgentLifecycleController(service: service)
    service.inspected = agentHealth(.healthy, detail: "Agent recovered after exit")

    controller.refresh()

    #expect(service.inspectCalls == 2)
    #expect(controller.health.state == .healthy)
    #expect(controller.health.detail == "Agent recovered after exit")
}

@MainActor
@Test
func agentLifecycleControllerReportsLoginItemsOpenFailureWithManualPath() {
    let service = StubAgentLifecycleService(
        inspected: agentHealth(.attention, detail: "Approval required"),
        enabled: agentHealth(.healthy, detail: "Agent is running"),
        disabled: agentHealth(.notConnected, detail: "Agent is disabled")
    )
    var openedURL: URL?
    let controller = AgentLifecycleController(service: service, openURL: {
        openedURL = $0
        return false
    })

    controller.openLoginItems()

    #expect(openedURL?.absoluteString == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    #expect(controller.loginItemsOpenFailure?.contains("General") == true)
    #expect(controller.loginItemsOpenFailure?.contains("Login Items") == true)

    controller.clearLoginItemsOpenFailure()
    #expect(controller.loginItemsOpenFailure == nil)
}

@MainActor
private final class StubAgentLifecycleService: AgentLifecycleServicing {
    var inspected: SourceHealth
    let enabled: SourceHealth
    let disabled: SourceHealth
    private(set) var inspectCalls = 0
    private(set) var enableCalls = 0
    private(set) var disableCalls = 0

    init(inspected: SourceHealth, enabled: SourceHealth, disabled: SourceHealth) {
        self.inspected = inspected
        self.enabled = enabled
        self.disabled = disabled
    }

    func inspect() -> SourceHealth {
        inspectCalls += 1
        return inspected
    }

    func enableAndInspect() -> SourceHealth {
        enableCalls += 1
        return enabled
    }

    func disableAndInspect() -> SourceHealth {
        disableCalls += 1
        return disabled
    }
}

private func agentHealth(_ state: HealthState, detail: String) -> SourceHealth {
    SourceHealth(
        id: .agent,
        title: "Zoid 666 Agent",
        eyebrow: "Autonomy",
        state: state,
        detail: detail,
        evidence: "Local test evidence",
        actionTitle: "Inspect"
    )
}
