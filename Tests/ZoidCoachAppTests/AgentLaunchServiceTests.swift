import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

struct AgentLaunchServiceTests {
    @MainActor
    @Test
    func qaRuntimeNeverInspectsRegistersOrUnregistersProductionService() throws {
        let runtimeEnvironment = try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", "/tmp/zoid-agent-launch-qa"],
            processEnvironment: [:]
        ).environment
        let registration = RecordingAgentServiceRegistration()
        let service = AgentLaunchService(
            runtimeEnvironment: runtimeEnvironment,
            service: registration
        )

        #expect(service.inspect().state == .unavailable)
        #expect(service.enableAndInspect().state == .unavailable)
        #expect(service.disableAndInspect().state == .unavailable)
        #expect(registration.statusReadCount == 0)
        #expect(registration.registerCount == 0)
        #expect(registration.unregisterCount == 0)
    }

    @Test
    func developmentPackageCannotTakeOwnershipFromTheInstalledApp() {
        #expect(AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/repo/.build/app/Zoid Coach.app")
        ))
        #expect(!AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/Users/example/Applications/Zoid Coach.app")
        ))
    }

    @Test
    func registrationFingerprintChangesWhenTheInstalledAppMoves() {
        let buildCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/tmp/build/Zoid Coach.app")
        )
        let installedCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid Coach.app")
        )

        #expect(buildCopy != installedCopy)
    }

    @Test
    func registrationFingerprintIsStableForTheSameBuildAndPath() {
        let first = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/../Applications/Zoid Coach.app")
        )
        let second = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid Coach.app")
        )

        #expect(first == second)
    }
}

@MainActor
private final class RecordingAgentServiceRegistration: AgentServiceRegistration {
    private(set) var statusReadCount = 0
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    var status: AgentRegistrationStatus {
        statusReadCount += 1
        return .enabled
    }

    func register() throws { registerCount += 1 }
    func unregister() throws { unregisterCount += 1 }
}
