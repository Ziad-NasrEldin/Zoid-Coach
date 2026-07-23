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

@Test
func signedDayStateFixturesRemainProductionDecodable() throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodayDashboardAgent(
        databaseURL: fixture.runtime.databaseURL
    ).snapshot()
    let backupURL = fixture.root.appendingPathComponent("original-snapshot.tsv")
    let fixtureScript = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/qa-zc013001-day-state-fixture.sh")
    defer {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? runDayStateFixture(
                fixtureScript,
                arguments: [
                    "cleanup",
                    "--database", fixture.runtime.databaseURL.path,
                    "--backup", backupURL.path,
                ]
            )
        }
    }

    try runDayStateFixture(
        fixtureScript,
        arguments: [
            "prepare",
            "--database", fixture.runtime.databaseURL.path,
            "--backup", backupURL.path,
        ]
    )

    let expectedModes: [(String, PlanningDayMode)] = [
        ("invitation", .invitation),
        ("snoozed", .snoozed),
        ("dismissed", .dismissed),
        ("planned", .planning),
        ("unplanned", .unplanned),
        ("active", .unplanned),
    ]
    for (state, expectedMode) in expectedModes {
        try runDayStateFixture(
            fixtureScript,
            arguments: [
                "set", state,
                "--database", fixture.runtime.databaseURL.path,
                "--backup", backupURL.path,
            ]
        )
        let snapshot = try #require(try TodaySnapshotStore(
            databaseURL: fixture.runtime.databaseURL,
            readOnly: true
        ).load())
        #expect(snapshot.planningStatus?.mode == expectedMode)
        #expect((snapshot.activeTask != nil) == (state == "active"))
    }

    try runDayStateFixture(
        fixtureScript,
        arguments: [
            "set", "preparing",
            "--database", fixture.runtime.databaseURL.path,
            "--backup", backupURL.path,
        ]
    )
    #expect(try TodaySnapshotStore(
        databaseURL: fixture.runtime.databaseURL,
        readOnly: true
    ).load() == nil)

    try runDayStateFixture(
        fixtureScript,
        arguments: [
            "cleanup",
            "--database", fixture.runtime.databaseURL.path,
            "--backup", backupURL.path,
        ]
    )
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

@Test
func producerShapedSnapshotFetchesRemainLimitedToExplicitWorkflows() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appSources = repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp")
    let allowedCallCounts = [
        "AppModel.swift": 2,
        "DashboardEndWorkdayFlow.swift": 2,
        "MenuBarCoachView.swift": 2,
    ]
    var observedCallCounts: [String: Int] = [:]
    let enumerator = try #require(FileManager.default.enumerator(
        at: appSources,
        includingPropertiesForKeys: nil
    ))

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        guard !fileURL.lastPathComponent.hasSuffix("Probe.swift") else { continue }
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let callCount = source
            .split(separator: "\n")
            .count { $0.contains(".fetchTodaySnapshot()") }
        guard callCount > 0 else { continue }
        observedCallCounts[fileURL.lastPathComponent] = callCount
    }

    #expect(observedCallCounts == allowedCallCounts)
}

@MainActor
@Test
func delayedForegroundStartupDoesNotReregisterProducerOrCreateSnapshot() async throws {
    let fixture = try TodaySnapshotOwnershipFixture()
    defer { fixture.remove() }
    _ = try TodaySnapshotStore(databaseURL: fixture.runtime.databaseURL)
    AgentLaunchService.recordSuccessfulExternalUnregistration(
        userDefaults: fixture.runtime.makeUserDefaults()
    )
    let registration = TodaySnapshotOwnershipNoopAgentRegistration()
    let model = fixture.makeAppModel(registration: registration)

    try await Task.sleep(for: .milliseconds(300))
    await model.refreshTodaySnapshot()

    #expect(registration.registerCount == 0)
    #expect(model.todaySnapshot == nil)
    #expect(try TodaySnapshotStore(
        databaseURL: fixture.runtime.databaseURL,
        readOnly: true
    ).load() == nil)
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
    func makeAppModel(
        registration: TodaySnapshotOwnershipNoopAgentRegistration
            = TodaySnapshotOwnershipNoopAgentRegistration()
    ) -> AppModel {
        AppModel(
            runtimeEnvironment: runtime,
            agentLaunchService: AgentLaunchService(
                runtimeEnvironment: runtime,
                service: registration
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
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func register() {
        registerCount += 1
        status = .enabled
    }

    func unregister() {
        unregisterCount += 1
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

private func runDayStateFixture(_ script: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let detail = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        throw TodaySnapshotOwnershipFixtureError.failed(detail)
    }
}

private enum TodaySnapshotOwnershipFixtureError: Error {
    case failed(String)
}
