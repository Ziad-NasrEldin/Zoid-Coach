import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func foregroundRefreshDoesNotGenerateAMissingTodaySnapshot() async throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodaySnapshotStore(databaseURL: fixture.runtime.databaseURL)
    let model = fixture.makeAppModel()

    await model.refreshTodaySnapshot()

    #expect(model.todaySnapshot == nil)
    #expect(try TodaySnapshotStore(
        databaseURL: fixture.runtime.databaseURL,
        readOnly: true
    ).load() == nil)
}

@Test
func explicitAgentGenerationStillPersistsTodaySnapshot() throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    let generated = try TodayDashboardAgent(
        databaseURL: fixture.runtime.databaseURL
    ).snapshot()

    #expect(generated.planningStatus?.mode == .invitation)
    #expect(try TodaySnapshotStore(
        databaseURL: fixture.runtime.databaseURL,
        readOnly: true
    ).load()?.planningStatus?.mode == .invitation)
}

@MainActor
@Test
func foregroundRefreshReadsPersistedInvitation() async throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodayDashboardAgent(
        databaseURL: fixture.runtime.databaseURL
    ).snapshot()
    let model = fixture.makeAppModel()

    await model.refreshTodaySnapshot()

    #expect(model.todaySnapshot?.planningStatus?.mode == .invitation)
}

private struct TodaySnapshotOwnershipFixture {
    let root: URL
    let runtime: RuntimeEnvironment

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-today-snapshot-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runtime = try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: .init(
                mode: .qa,
                qaRunRoot: root,
                appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
            ),
            executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
        ).environment
    }

    @MainActor
    func makeAppModel() -> AppModel {
        AppModel(
            runtimeEnvironment: runtime,
            agentLaunchService: AgentLaunchService(
                runtimeEnvironment: runtime,
                service: TodaySnapshotOwnershipNoopAgentRegistration()
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class TodaySnapshotOwnershipNoopAgentRegistration: AgentServiceRegistration {
    var status: AgentRegistrationStatus = .notRegistered

    func register() {
        status = .enabled
    }

    func unregister() {
        status = .notRegistered
    }
}
