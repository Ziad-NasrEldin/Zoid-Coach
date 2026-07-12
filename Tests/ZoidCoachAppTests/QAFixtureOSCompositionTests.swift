import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
@Test
func signedQAFixtureFlowsFromSeedThroughAppAgentMutationAndAppRefresh() async throws {
    let fixture = try signedQARuntime("app-agent-flow")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let seedTask = SourceTask(
        id: "seed-task", title: "Seed task", listIdentifier: "inbox",
        priority: 1, dueDate: nil, notes: nil, isCompleted: false
    )
    try writeControl(
        .init(
            operation: .seed,
            seed: .init(
                permissions: [
                    .reminders: .granted,
                    .calendar: .granted,
                    .notifications: .granted
                ],
                reminders: [seedTask]
            )
        ),
        runtime: fixture.environment
    )
    var productionConstructionCount = 0
    let liveFactory = AppOSServiceFactory(
        reminders: { productionConstructionCount += 1; return RemindersService() },
        calendar: { productionConstructionCount += 1; return CalendarService() },
        notifications: { productionConstructionCount += 1; return NotificationService() }
    )
    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        liveServiceFactory: liveFactory,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        )
    )
    await model.refreshQAFixtureState()
    #expect(model.reminderTasks.map(\.id) == ["seed-task"])
    #expect(productionConstructionCount == 0)
    #expect(FileManager.default.fileExists(atPath: fixture.root
        .appendingPathComponent(QAFixtureOSComposition.snapshotRelativePath).path))
    #expect(!FileManager.default.fileExists(atPath: fixture.root
        .appendingPathComponent(QAFixtureOSComposition.controlRelativePath).path))

    let agentAdapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    let created = try await agentAdapter.create(
        title: "Agent-created", dueDate: nil,
        listIdentifier: "inbox", metadataMarker: "agent-created"
    )
    await model.refreshQAFixtureState()

    #expect(Set(model.reminderTasks.map(\.id)) == ["seed-task", created.id])
    #expect(try model.qaOSFixtureAdapter?.snapshot().reminders.count == 2)
    let restarted = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    #expect(try restarted.snapshot().reminders.count == 2)
}

@MainActor
@Test
func fixtureServicesExposeDeniedAndDeferredPermissionStates() async throws {
    let fixture = try signedQARuntime("permissions")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [
        .reminders: .denied,
        .calendar: .notDetermined,
        .notifications: .restricted
    ]))

    let reminders = QAFixtureRemindersService(adapter: adapter)
    let calendar = QAFixtureCalendarService(adapter: adapter)
    let notifications = QAFixtureNotificationService(adapter: adapter)

    #expect(await reminders.inspect().state == .attention)
    #expect(calendar.selectionAvailability == .needsPermission)
    #expect(await notifications.inspect().state == .attention)
    #expect(await reminders.fetchIncompleteTasks().isUnavailable)
}

@Test
func fixtureNotificationDeliveryAndActionRoutesToPromptInbox() async throws {
    let fixture = try signedQARuntime("notification-action")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let databaseURL = fixture.root.appendingPathComponent("prompt.sqlite")
    let promptStore = try PromptInboxStore(
        databaseURL: databaseURL,
        now: { fixture.now },
        makeID: { "prompt-1" }
    )
    let episode = try promptStore.enqueue(.init(
        decisionKey: "plan-ready",
        type: PromptNotificationCategory.planReady.rawValue,
        title: "Plan ready",
        summary: "Review the plan",
        actions: [.init(kind: .acceptPlan, title: "Accept")]
    )).episode
    let coordinator = PromptNotificationCoordinator(
        promptStore: promptStore,
        fixtureAdapter: adapter,
        runtimeEnvironment: fixture.environment
    )
    #expect(try await coordinator.schedule(episode))
    _ = try QAFixtureOSComposition.apply(.init(
        operation: .notificationAction,
        notificationID: episode.id,
        actionIdentifier: PromptActionKind.acceptPlan.rawValue
    ), to: adapter)
    try await coordinator.processFixtureActions()

    #expect(try promptStore.episode(promptID: episode.id)?.state == .responded)
    #expect(try adapter.snapshot().notifications.first?.status == .responded)
}

@Test
func fixtureCalendarRefusesMutationOfExternalCommitment() async throws {
    let fixture = try signedQARuntime("owned-refusal")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let external = CalendarCommitment(
        id: "external", title: "External", start: fixture.now,
        end: fixture.now.addingTimeInterval(600), calendarIdentifier: "work"
    )
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(
        permissions: [.calendar: .granted],
        calendarCommitments: [external]
    ))

    await #expect(throws: ActionSourceError.ownershipViolation) {
        try await adapter.apply(.deleteOwnedBlock(
            identifier: external.id,
            ownershipToken: "not-owned"
        ))
    }
}

@Test
func controlRequestResumesAfterAProcessingFailure() throws {
    let fixture = try signedQARuntime("control-resume")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    _ = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    let requestURL = fixture.root.appendingPathComponent(
        QAFixtureOSComposition.controlRelativePath
    )
    let processingURL = requestURL.deletingLastPathComponent()
        .appendingPathComponent("os-fixture-request.processing.json")
    try Data("{ malformed".utf8).write(to: requestURL)

    #expect(throws: (any Error).self) {
        try QAFixtureOSComposition.makeAuthorizedAdapter(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now)
        )
    }
    #expect(FileManager.default.fileExists(atPath: processingURL.path))
    #expect(!FileManager.default.fileExists(atPath: requestURL.path))

    try JSONEncoder().encode(QAFixtureOSControlRequest(operation: .snapshot))
        .write(to: processingURL, options: .atomic)
    _ = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )

    #expect(!FileManager.default.fileExists(atPath: processingURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.root
        .appendingPathComponent(QAFixtureOSComposition.snapshotRelativePath).path))
}

@Test
func controlDirectorySymlinkFailsClosed() throws {
    let fixture = try signedQARuntime("control-symlink")
    let outside = try testRoot("control-symlink-outside")
    defer {
        try? FileManager.default.removeItem(at: fixture.root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createSymbolicLink(
        at: fixture.root.appendingPathComponent("QA Control"),
        withDestinationURL: outside
    )

    #expect(throws: (any Error).self) {
        try QAFixtureOSComposition.makeAuthorizedAdapter(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now)
        )
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

@MainActor
@Test
func appSurfacesSignedQAFixtureStartupFailure() async throws {
    let fixture = try signedQARuntime("app-startup-failure")
    let outside = try testRoot("app-startup-failure-outside")
    defer {
        try? FileManager.default.removeItem(at: fixture.root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createSymbolicLink(
        at: fixture.root.appendingPathComponent("OS Fixtures"),
        withDestinationURL: outside
    )
    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        )
    )
    model.runSourceCheck()
    let deadline = Date().addingTimeInterval(2)
    while model.sources.contains(where: { $0.state == .checking }), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.qaOSFixtureAdapter == nil)
    #expect(model.sources.first(where: { $0.id == .reminders })?.detail
        .hasPrefix("QA fixture startup failed:") == true)
    #expect(model.sources.first(where: { $0.id == .calendar })?.detail
        .hasPrefix("QA fixture startup failed:") == true)
    #expect(model.sources.first(where: { $0.id == .notifications })?.detail
        .hasPrefix("QA fixture startup failed:") == true)
}

@Test
func unbundledOrMismatchedQAIdentityCannotEnableFixtures() throws {
    let root = try testRoot("invalid-identity")
    defer { try? FileManager.default.removeItem(at: root) }
    let unbundled = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:],
        executableSigningIdentifier: nil
    ).environment

    #expect(throws: QAFixtureOSCompositionError.signedQAPackageRequired) {
        try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: unbundled)
    }
    #expect(throws: AgentOSAdapterBoundaryError.self) {
        try AgentOSAdapterBoundary.validate(
            runtimeEnvironment: unbundled,
            operations: [.synchronizeReminders]
        )
    }
}

@Test
func signedQABoundaryAllowsOnlyFixtureBackedOperations() throws {
    let fixture = try signedQARuntime("signed-boundary")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    _ = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )

    try AgentOSAdapterBoundary.validate(
        runtimeEnvironment: fixture.environment,
        operations: Set(AgentOSAdapterOperation.allCases),
        fixtureAuthorization: try AgentOSAdapterBoundary.authorizeFixture(
            runtimeEnvironment: fixture.environment
        )
    )
    #expect(throws: AgentOSAdapterBoundaryError.self) {
        try AgentOSAdapterBoundary.validate(
            runtimeEnvironment: fixture.environment,
            operations: [.synchronizeCalendar]
        )
    }
}

@Test
func signedQACompositionCreatesOnlyItsMissingFinalRunRoot() throws {
    let parent = try testRoot("missing-root-parent")
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appendingPathComponent("signed-run-root", isDirectory: true)
    let environment = try RuntimeEnvironment.resolve(
        arguments: [], processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa, qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment

    _ = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: environment,
        clock: .fixed(Date(timeIntervalSince1970: 1_735_732_800))
    )

    #expect(FileManager.default.fileExists(atPath: root.path))
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("OS Fixtures/state.json").path
    ))
}

private struct SignedQAFixture {
    let root: URL
    let environment: RuntimeEnvironment
    let now: Date
}

private func signedQARuntime(_ label: String) throws -> SignedQAFixture {
    let root = try testRoot(label)
    let environment = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    return .init(
        root: root,
        environment: environment,
        now: Date(timeIntervalSince1970: 1_735_732_800)
    )
}

private func testRoot(_ label: String) throws -> URL {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot
        .appendingPathComponent(".build/os-fixture-wiring-tests", isDirectory: true)
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeControl(
    _ request: QAFixtureOSControlRequest,
    runtime: RuntimeEnvironment
) throws {
    guard case let .qa(root) = runtime.mode else { return }
    let url = root.appendingPathComponent(QAFixtureOSComposition.controlRelativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try JSONEncoder().encode(request).write(to: url, options: .atomic)
}

@MainActor
private final class NoopAgentRegistration: AgentServiceRegistration {
    var status: AgentRegistrationStatus = .notRegistered
    func register() { status = .enabled }
    func unregister() { status = .notRegistered }
}

private extension ReminderTaskLoad {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
