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

    @MainActor
    @Test
    func packagedQAUsesOnlyItsDedicatedServiceAndSupportsFullUIControl() throws {
        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-agent-launch-packaged-qa-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: runRoot) }
        let runtimeEnvironment = try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: .init(
                mode: .qa,
                qaRunRoot: runRoot,
                appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
            ),
            executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
        ).environment
        let production = RecordingAgentServiceRegistration(status: .enabled)
        let qa = RecordingAgentServiceRegistration(status: .notRegistered)
        var productionConstructionCount = 0
        var qaPlistNames: [String] = []
        let factory = AgentServiceRegistrationFactory(
            production: { _ in
                productionConstructionCount += 1
                return production
            },
            qa: { plistName in
                qaPlistNames.append(plistName)
                return qa
            }
        )
        let service = AgentLaunchService(
            runtimeEnvironment: runtimeEnvironment,
            registrationFactory: factory,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666 QA.app"),
            buildVersion: "qa-1"
        )

        #expect(service.inspect().state == .notConnected)
        #expect(service.enableAndInspect().state == .healthy)
        #expect(service.disableAndInspect().state == .notConnected)
        #expect(qaPlistNames == [RuntimeIdentity.qa.launchAgentPlistName])
        #expect(qa.registerCount == 1)
        #expect(qa.unregisterCount == 1)
        #expect(productionConstructionCount == 0)
        #expect(production.statusReadCount == 0)
        #expect(production.registerCount == 0)
        #expect(production.unregisterCount == 0)
    }

    @Test
    func developmentPackageCannotTakeOwnershipFromTheInstalledApp() {
        #expect(AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/repo/.build/app/Zoid 666.app")
        ))
        #expect(!AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/Users/example/Applications/Zoid 666.app")
        ))
    }

    @Test
    func registrationFingerprintChangesWhenTheInstalledAppMoves() {
        let buildCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/tmp/build/Zoid 666.app")
        )
        let installedCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app")
        )

        #expect(buildCopy != installedCopy)
    }

    @Test
    func registrationFingerprintIsStableForTheSameBuildAndPath() {
        let first = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/../Applications/Zoid 666.app")
        )
        let second = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app")
        )

        #expect(first == second)
    }
}

@MainActor
private final class RecordingAgentServiceRegistration: AgentServiceRegistration {
    private(set) var statusReadCount = 0
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    private var currentStatus: AgentRegistrationStatus

    init(status: AgentRegistrationStatus = .enabled) {
        currentStatus = status
    }

    var status: AgentRegistrationStatus {
        statusReadCount += 1
        return currentStatus
    }

    func register() throws {
        registerCount += 1
        currentStatus = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        currentStatus = .notRegistered
    }
}
