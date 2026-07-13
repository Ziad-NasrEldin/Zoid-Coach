import Foundation
import SQLite3
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
        #expect(service.repairAndInspect().state == .unavailable)
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
            buildVersion: "qa-1",
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            heartbeat: { Date(timeIntervalSince1970: 1_799_999_995) }
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

    @MainActor
    @Test
    func enabledRegistrationRequiresAFreshRuntimeHeartbeatToBeHealthy() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let registration = RecordingAgentServiceRegistration(status: .enabled)
        let missing = AgentLaunchService(
            service: registration,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app"),
            now: { now },
            heartbeat: { nil }
        )
        let stale = AgentLaunchService(
            service: registration,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app"),
            now: { now },
            heartbeat: { now.addingTimeInterval(-300) },
            heartbeatFreshness: 120
        )
        let running = AgentLaunchService(
            service: registration,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app"),
            now: { now },
            heartbeat: { now.addingTimeInterval(-5) },
            heartbeatFreshness: 120
        )

        #expect(missing.inspect().state == .attention)
        #expect(missing.launchAtLoginStatus() == .enabled)
        #expect(missing.inspect().detail.contains("has not checked in"))
        #expect(stale.inspect().state == .attention)
        #expect(stale.inspect().evidence.contains("5 minutes ago"))
        #expect(running.inspect().state == .healthy)
        #expect(running.inspect().detail == "Background agent is running")
    }

    @MainActor
    @Test
    func launchAtLoginStatusRemainsEnabledWhenHeartbeatIsStaleAndCanBeDisabled() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let registration = RecordingAgentServiceRegistration(status: .enabled)
        let service = AgentLaunchService(
            service: registration,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app"),
            now: { now },
            heartbeat: { now.addingTimeInterval(-300) }
        )

        #expect(service.inspect().state == .attention)
        #expect(service.launchAtLoginStatus() == .enabled)

        let disabled = service.disableAndInspect()

        #expect(disabled.state == .notConnected)
        #expect(service.launchAtLoginStatus() == .notRegistered)
        #expect(registration.unregisterCount == 1)
    }

    @MainActor
    @Test
    func forcedRepairReregistersEvenWhenRegistrationLooksEnabled() {
        let registration = RecordingAgentServiceRegistration(status: .enabled)
        let service = AgentLaunchService(
            service: registration,
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid 666.app"),
            buildVersion: "8",
            heartbeat: { Date() }
        )

        _ = service.repairAndInspect()

        #expect(registration.unregisterCount == 1)
        #expect(registration.registerCount == 1)
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

    @Test
    func heartbeatReaderIsReadOnlyAndReturnsTheCanonicalAgentCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-heartbeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing.sqlite")
        #expect(AgentLaunchService.readAgentHeartbeat(databaseURL: missing) == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))

        let databaseURL = root.appendingPathComponent("zoid.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let opened = try #require(database)
        defer { sqlite3_close(opened) }
        #expect(sqlite3_exec(
            opened,
            "CREATE TABLE processing_checkpoints(source_id TEXT PRIMARY KEY, last_success_at_utc TEXT); INSERT INTO processing_checkpoints VALUES('agent-runtime','2027-01-15T10:11:12Z');",
            nil,
            nil,
            nil
        ) == SQLITE_OK)

        #expect(AgentLaunchService.readAgentHeartbeat(databaseURL: databaseURL)
            == ISO8601DateFormatter().date(from: "2027-01-15T10:11:12Z"))
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
