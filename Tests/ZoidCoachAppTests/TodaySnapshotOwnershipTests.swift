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

@MainActor
@Test
func menuForegroundRefreshDoesNotGenerateAMissingTodaySnapshot() async throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodaySnapshotStore(databaseURL: fixture.runtime.databaseURL)
    let loader = ReadOnlyTodaySnapshotLoader(runtimeEnvironment: fixture.runtime)
    let controller = MenuBarCoachController(
        client: TodaySnapshotOwnershipUnexpectedMenuClient(),
        loadTodaySnapshot: loader.load
    )

    await controller.refresh()

    #expect(controller.snapshot == nil)
    #expect(try TodaySnapshotStore(
        databaseURL: fixture.runtime.databaseURL,
        readOnly: true
    ).load() == nil)
}

@MainActor
@Test
func menuForegroundRefreshReadsPersistedInvitation() async throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodayDashboardAgent(
        databaseURL: fixture.runtime.databaseURL
    ).snapshot()
    let loader = ReadOnlyTodaySnapshotLoader(runtimeEnvironment: fixture.runtime)
    let controller = MenuBarCoachController(
        client: TodaySnapshotOwnershipUnexpectedMenuClient(),
        loadTodaySnapshot: loader.load
    )

    await controller.refresh()

    #expect(controller.snapshot?.planningStatus?.mode == .invitation)
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

private actor TodaySnapshotOwnershipUnexpectedMenuClient: MenuBarTodayClient {
    func fetchTodaySnapshot() throws -> TodaySnapshot {
        Issue.record("Foreground menu refresh must not call the producer-shaped XPC fetch")
        throw TodaySnapshotOwnershipUnexpectedMenuClientError.unexpectedCall
    }

    func apply(_ command: TaskActivityCommand, taskID: String) throws -> TodaySnapshot {
        Issue.record("Foreground menu refresh must not apply a task command")
        throw TodaySnapshotOwnershipUnexpectedMenuClientError.unexpectedCall
    }

    func blockTask(taskID: String, reason: String) throws -> TodaySnapshot {
        Issue.record("Foreground menu refresh must not block a task")
        throw TodaySnapshotOwnershipUnexpectedMenuClientError.unexpectedCall
    }
}

private enum TodaySnapshotOwnershipUnexpectedMenuClientError: Error {
    case unexpectedCall
}
