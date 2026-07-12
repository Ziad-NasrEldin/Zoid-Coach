import Darwin
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
            requestID: "seed-app-agent-flow",
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
        requestID: "notification-action",
        operation: .notificationAction,
        notificationID: episode.id,
        actionIdentifier: PromptActionKind.acceptPlan.rawValue
    ), runtimeEnvironment: fixture.environment, to: adapter)
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

    #expect(throws: QAFixtureOSCompositionError.malformedControlEncoding) {
        try QAFixtureOSComposition.makeAuthorizedAdapter(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now)
        )
    }
    #expect(FileManager.default.fileExists(atPath: processingURL.path))
    #expect(!FileManager.default.fileExists(atPath: requestURL.path))

    try JSONEncoder().encode(QAFixtureOSControlRequest(
        requestID: "recovered-snapshot",
        operation: .snapshot
    ))
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
func controlRequestDoesNotReplayAfterCrashFollowingMutationCommit() async throws {
    let fixture = try signedQARuntime("control-after-mutation")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeControl(.init(
        requestID: "seed-after-mutation",
        operation: .seed,
        seed: .init(
            permissions: [.reminders: .granted],
            reminders: [.init(
                id: "seed-once",
                title: "Seed once",
                listIdentifier: "inbox",
                priority: 1,
                dueDate: nil,
                notes: nil,
                isCompleted: false
            )]
        )
    ), runtime: fixture.environment)

    #expect(throws: InjectedControlInterruption.self) {
        try QAFixtureOSComposition.makeAuthorizedComposition(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now),
            controlCheckpoint: { checkpoint in
                if checkpoint == .mutationCommitted {
                    throw InjectedControlInterruption.stopped
                }
            }
        )
    }
    let committed = try rawAdapter(for: fixture)
    let committedSnapshot = try committed.snapshot()
    #expect(committedSnapshot.reminders.map(\.id) == ["seed-once"])
    _ = try await committed.create(
        title: "Post-crash mutation",
        dueDate: nil,
        listIdentifier: "inbox",
        metadataMarker: "post-crash"
    )
    let afterPostCrashMutation = try committed.snapshot()
    #expect(afterPostCrashMutation.audit.count == committedSnapshot.audit.count + 1)

    let recovered = try QAFixtureOSComposition.makeAuthorizedComposition(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    ).adapter.snapshot()
    #expect(recovered == afterPostCrashMutation)
    #expect(Set(recovered.reminders.map(\.title)) == ["Seed once", "Post-crash mutation"])
}

@Test
func controlRequestDoesNotReplayAfterCrashFollowingSnapshotPersistence() async throws {
    let fixture = try signedQARuntime("control-after-snapshot")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let notificationID = try await adapter.schedule(.init(
        category: PromptNotificationCategory.planReady.rawValue,
        title: "Plan",
        body: "Ready",
        promptID: "prompt-after-snapshot",
        deliveryDate: fixture.now
    ))
    try writeControl(.init(
        requestID: "action-after-snapshot",
        operation: .notificationAction,
        notificationID: notificationID,
        actionIdentifier: PromptActionKind.acceptPlan.rawValue
    ), runtime: fixture.environment)

    #expect(throws: InjectedControlInterruption.self) {
        try QAFixtureOSComposition.makeAuthorizedComposition(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now),
            controlCheckpoint: { checkpoint in
                if checkpoint == .snapshotPersisted {
                    throw InjectedControlInterruption.stopped
                }
            }
        )
    }
    let committed = try rawAdapter(for: fixture).snapshot()
    #expect(committed.notifications.first?.status == .responded)
    let recovered = try QAFixtureOSComposition.makeAuthorizedComposition(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    ).adapter.snapshot()
    #expect(recovered == committed)
}

@Test
func everyControlOperationIsIdempotentByRequestID() async throws {
    let fixture = try signedQARuntime("control-idempotency")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try rawAdapter(for: fixture)
    #expect(throws: QAFixtureOSCompositionError.invalidRequestIdentifier) {
        try QAFixtureOSComposition.apply(
            .init(requestID: " ", operation: .snapshot),
            runtimeEnvironment: fixture.environment,
            to: adapter
        )
    }
    let seed = QAFixtureOSControlRequest(
        requestID: "seed-idempotent",
        operation: .seed,
        seed: .init(permissions: [.notifications: .granted])
    )
    let firstSeed = try QAFixtureOSComposition.apply(
        seed,
        runtimeEnvironment: fixture.environment,
        to: adapter
    )
    #expect(try QAFixtureOSComposition.apply(
        seed,
        runtimeEnvironment: fixture.environment,
        to: adapter
    ) == firstSeed)

    let reset = QAFixtureOSControlRequest(
        requestID: "reset-idempotent",
        operation: .reset,
        seed: .init(permissions: [.notifications: .granted])
    )
    let firstReset = try QAFixtureOSComposition.apply(
        reset,
        runtimeEnvironment: fixture.environment,
        to: adapter
    )
    #expect(try QAFixtureOSComposition.apply(
        reset,
        runtimeEnvironment: fixture.environment,
        to: adapter
    ) == firstReset)
    #expect(try QAFixtureOSComposition.apply(
        seed,
        runtimeEnvironment: fixture.environment,
        to: adapter
    ) == firstSeed)
    #expect(try adapter.snapshot() == firstReset)

    let notificationID = try await adapter.schedule(.init(
        category: PromptNotificationCategory.planReady.rawValue,
        title: "Plan",
        body: "Ready",
        promptID: "idempotent-prompt",
        deliveryDate: fixture.now
    ))
    let action = QAFixtureOSControlRequest(
        requestID: "action-idempotent",
        operation: .notificationAction,
        notificationID: notificationID,
        actionIdentifier: PromptActionKind.acceptPlan.rawValue
    )
    let firstAction = try QAFixtureOSComposition.apply(
        action,
        runtimeEnvironment: fixture.environment,
        to: adapter
    )
    #expect(try QAFixtureOSComposition.apply(
        action,
        runtimeEnvironment: fixture.environment,
        to: adapter
    ) == firstAction)

    let snapshot = QAFixtureOSControlRequest(
        requestID: "snapshot-idempotent",
        operation: .snapshot
    )
    let firstSnapshot = try QAFixtureOSComposition.apply(
        snapshot,
        runtimeEnvironment: fixture.environment,
        to: adapter
    )
    #expect(try QAFixtureOSComposition.apply(
        snapshot,
        runtimeEnvironment: fixture.environment,
        to: adapter
    ) == firstSnapshot)
    #expect(throws: QAFixtureStateError.controlRequestConflict("snapshot-idempotent")) {
        try QAFixtureOSComposition.apply(
            .init(requestID: "snapshot-idempotent", operation: .reset),
            runtimeEnvironment: fixture.environment,
            to: adapter
        )
    }
}

@Test
func notificationControlRejectsUnknownAndForeignNamespacedActionsBeforeMutation() async throws {
    let fixture = try signedQARuntime("invalid-actions")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try rawAdapter(for: fixture)
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let notificationID = try await adapter.schedule(.init(
        category: PromptNotificationCategory.planReady.rawValue,
        title: "Plan",
        body: "Ready",
        promptID: "invalid-action-prompt",
        deliveryDate: fixture.now
    ))
    let before = try adapter.snapshot()
    for (requestID, action) in [
        ("unknown-action", "destroy_everything"),
        ("foreign-action", "com.ziadnasreldin.ZoidCoach.prompt.action.ACCEPT_PLAN"),
        ("category-mismatch", PromptActionKind.addMeeting.rawValue)
    ] {
        #expect(throws: QAFixtureOSCompositionError.invalidNotificationAction(action)) {
            try QAFixtureOSComposition.apply(
                .init(
                    requestID: requestID,
                    operation: .notificationAction,
                    notificationID: notificationID,
                    actionIdentifier: action
                ),
                runtimeEnvironment: fixture.environment,
                to: adapter
            )
        }
        #expect(try adapter.snapshot() == before)
    }
}

@Test
func fixtureNotificationActionMatrixMatchesEveryLiveCategoryAction() {
    let identity = RuntimeIdentity.qa.notification
    let allowed: [PromptNotificationCategory: Set<PromptActionKind>] = [
        .planReady: [.acceptPlan, .reviewPlan],
        .meetingCandidate: [.addMeeting, .editMeeting, .ignore],
        .planChanged: [.reviewPlan, .undoPlanChange],
        .wakeIntervention: []
    ]
    for category in PromptNotificationCategory.allCases {
        for action in PromptActionKind.allCases {
            let expected = allowed[category, default: []].contains(action) ? action : nil
            #expect(PromptNotificationCoordinator.fixtureActionKind(
                identifier: action.rawValue,
                category: category.rawValue,
                notificationIdentity: identity
            ) == expected)
            #expect(PromptNotificationCoordinator.fixtureActionKind(
                identifier: PromptNotificationCoordinator.actionIdentifier(
                    action,
                    notificationIdentity: identity
                ),
                category: category.rawValue,
                notificationIdentity: identity
            ) == expected)
        }
    }
    #expect(PromptNotificationCoordinator.fixtureActionKind(
        identifier: "com.ziadnasreldin.ZoidCoach.prompt.action.ACCEPT_PLAN",
        category: PromptNotificationCategory.planReady.rawValue,
        notificationIdentity: identity
    ) == nil)
}

@Test
func concurrentAppAgentMutationsAndControlIngestionLoseNoState() async throws {
    let fixture = try signedQARuntime("concurrent-control")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let appAdapter = try rawAdapter(for: fixture)
    let agentAdapter = try rawAdapter(for: fixture)
    try appAdapter.reset(to: .init(permissions: [.reminders: .granted]))
    try writeControl(.init(
        requestID: "concurrent-snapshot",
        operation: .snapshot
    ), runtime: fixture.environment)
    let gate = AsyncStartGate(participants: 3)

    async let appTask: SourceTask = {
        await gate.arriveAndWait()
        return try await appAdapter.create(
            title: "App task",
            dueDate: nil,
            listIdentifier: "inbox",
            metadataMarker: "app-task"
        )
    }()
    async let agentTask: SourceTask = {
        await gate.arriveAndWait()
        return try await agentAdapter.create(
            title: "Agent task",
            dueDate: nil,
            listIdentifier: "inbox",
            metadataMarker: "agent-task"
        )
    }()
    async let control: AuthorizedQAFixtureOSComposition = {
        await gate.arriveAndWait()
        return try QAFixtureOSComposition.makeAuthorizedComposition(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now)
        )
    }()
    _ = try await (appTask, agentTask, control)

    let final = try rawAdapter(for: fixture).snapshot()
    #expect(Set(final.reminders.map(\.title)) == ["App task", "Agent task"])
    #expect(!FileManager.default.fileExists(atPath: fixture.root
        .appendingPathComponent(QAFixtureOSComposition.controlRelativePath).path))
}

@Test
func childProcessAppAgentMutationsContendWithControlIngestion() throws {
    let fixture = try signedQARuntime("child-process-control")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try rawAdapter(for: fixture)
    try adapter.reset(to: .init(permissions: [.reminders: .granted]))
    try writeControl(.init(
        requestID: "child-process-snapshot",
        operation: .snapshot
    ), runtime: fixture.environment)

    let roles = ["app", "agent"]
    let children = try roles.map { role in
        try launchFixtureMutationChild(role: role, fixture: fixture)
    }
    let readyURLs = roles.map {
        fixture.root.appendingPathComponent("child-\($0).ready")
    }
    try waitForFiles(readyURLs)
    let goURL = fixture.root.appendingPathComponent("children.go")
    let attemptingURLs = roles.map {
        fixture.root.appendingPathComponent("child-\($0).attempting")
    }
    _ = try QAFixtureOSComposition.makeAuthorizedComposition(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now),
        storageCheckpoint: { checkpoint in
            guard case .beforeStateCommit = checkpoint else { return }
            _ = FileManager.default.createFile(atPath: goURL.path, contents: Data())
            try waitForFiles(attemptingURLs)
        }
    )
    for child in children {
        child.waitUntilExit()
        #expect(child.terminationStatus == 0)
    }

    let final = try rawAdapter(for: fixture).snapshot()
    #expect(Set(final.reminders.map(\.title)) == ["Child app task", "Child agent task"])
}

@Test
func fixtureChildProcessMutationWorker() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let rootPath = environment["ZOID_FIXTURE_CHILD_ROOT"],
          let role = environment["ZOID_FIXTURE_CHILD_ROLE"] else { return }
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let fixture = SignedQAFixture(
        root: root,
        environment: runtime,
        now: Date(timeIntervalSince1970: 1_735_732_800)
    )
    _ = FileManager.default.createFile(
        atPath: root.appendingPathComponent("child-\(role).ready").path,
        contents: Data()
    )
    try waitForFiles([root.appendingPathComponent("children.go")])
    _ = FileManager.default.createFile(
        atPath: root.appendingPathComponent("child-\(role).attempting").path,
        contents: Data()
    )
    _ = try await rawAdapter(for: fixture).create(
        title: "Child \(role) task",
        dueDate: nil,
        listIdentifier: "inbox",
        metadataMarker: "child-\(role)"
    )
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
    let expectedDetail = "QA fixture startup failed: The fixture refused an unsafe filesystem entry: OS Fixtures"
    #expect(model.sources.first(where: { $0.id == .reminders })?.detail
        == expectedDetail)
    #expect(model.sources.first(where: { $0.id == .calendar })?.detail
        == expectedDetail)
    #expect(model.sources.first(where: { $0.id == .notifications })?.detail
        == expectedDetail)
}

@MainActor
@Test
func appSurfacesExactMalformedControlRecoveryCopy() async throws {
    let fixture = try signedQARuntime("app-malformed-control")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let requestURL = fixture.root.appendingPathComponent(
        QAFixtureOSComposition.controlRelativePath
    )
    try FileManager.default.createDirectory(
        at: requestURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("{ malformed".utf8).write(to: requestURL)
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

    let expected = "QA fixture startup failed: The QA OS fixture control request is not valid JSON or uses unsupported field values. Fix the processing request and relaunch."
    #expect(model.qaOSFixtureAdapter == nil)
    #expect(model.sources.first(where: { $0.id == .reminders })?.detail == expected)
    #expect(model.sources.first(where: { $0.id == .calendar })?.detail == expected)
    #expect(model.sources.first(where: { $0.id == .notifications })?.detail == expected)
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
func fixtureErrorsExposeActionableLocalizedDescriptions() {
    #expect(QAFixtureOSCompositionError.signedQAPackageRequired.localizedDescription
        == "QA OS fixtures require a signed QA app or agent with the embedded QA run root.")
    #expect(QAFixtureOSCompositionError.invalidRequestIdentifier.localizedDescription
        == "The QA OS fixture control request requires a non-empty requestID for exactly-once recovery.")
    #expect(QAFixtureStateError.unsafeFilesystemEntry("OS Fixtures").localizedDescription
        == "The fixture refused an unsafe filesystem entry: OS Fixtures")
    #expect(QAFixtureStateError.controlRequestConflict("request-1").localizedDescription
        == "The fixture control requestID 'request-1' was reused with different content.")
}

@Test
func downstreamCodeCannotForgeFixtureAuthorization() throws {
    let root = try testRoot("authorization-compile-guard")
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("ForgeAuthorization.swift")
    let source = """
    import Foundation
    import ZoidCoachInfrastructure

    func forge(_ adapter: DeterministicOSFixtureAdapters, root: URL) {
        _ = AgentOSFixtureAuthorization(adapter: adapter, runRoot: root)
    }
    """
    try Data(source.utf8).write(to: sourceURL)
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = repositoryRoot.appendingPathComponent(
        ".build/arm64-apple-macosx/debug/Modules"
    )
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "swiftc", "-typecheck", "-I", modules.path, sourceURL.path
    ]
    process.standardOutput = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    let error = String(
        decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )

    #expect(process.terminationStatus != 0)
    #expect(error.contains("inaccessible due to 'fileprivate' protection level"))
}

@Test
func signedQABoundaryAllowsOnlyFixtureBackedOperations() throws {
    let fixture = try signedQARuntime("signed-boundary")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    _ = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )

    let composition = try QAFixtureOSComposition.makeAuthorizedComposition(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try AgentOSAdapterBoundary.validate(
        runtimeEnvironment: fixture.environment,
        operations: Set(AgentOSAdapterOperation.allCases),
        fixtureAuthorization: composition.authorization,
        fixtureAdapter: composition.adapter
    )
    #expect(throws: AgentOSAdapterBoundaryError.self) {
        try AgentOSAdapterBoundary.validate(
            runtimeEnvironment: fixture.environment,
            operations: [.synchronizeCalendar]
        )
    }
    let substitutedAdapter = try rawAdapter(for: fixture)
    #expect(throws: AgentOSAdapterBoundaryError.self) {
        try AgentOSAdapterBoundary.validate(
            runtimeEnvironment: fixture.environment,
            operations: [.synchronizeReminders],
            fixtureAuthorization: composition.authorization,
            fixtureAdapter: substitutedAdapter
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

private enum InjectedControlInterruption: Error {
    case stopped
}

private actor AsyncStartGate {
    private let participants: Int
    private var arrived = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
        self.participants = participants
    }

    func arriveAndWait() async {
        arrived += 1
        if arrived == participants {
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private struct SignedQAFixture {
    let root: URL
    let environment: RuntimeEnvironment
    let now: Date
}

private func rawAdapter(for fixture: SignedQAFixture) throws -> DeterministicOSFixtureAdapters {
    try DeterministicOSFixtureAdapters(
        workspace: QAFixtureWorkspace(runtimeEnvironment: fixture.environment),
        clock: .fixed(fixture.now),
        stableID: { kind, index in "qa-\(kind.rawValue)-\(index)" }
    )
}

private func launchFixtureMutationChild(
    role: String,
    fixture: SignedQAFixture
) throws -> Process {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let process = Process()
    process.executableURL = URL(fileURLWithPath:
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
    )
    let bundleExecutable = repositoryRoot.appendingPathComponent(
        ".build/arm64-apple-macosx/debug/ZoidCoachPackageTests.xctest/Contents/MacOS/ZoidCoachPackageTests"
    ).path
    process.arguments = [
        "--test-bundle-path", bundleExecutable,
        "--filter", "fixtureChildProcessMutationWorker",
        bundleExecutable,
        "--testing-library", "swift-testing"
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["ZOID_FIXTURE_CHILD_ROOT"] = fixture.root.path
    environment["ZOID_FIXTURE_CHILD_ROLE"] = role
    process.environment = environment
    process.currentDirectoryURL = repositoryRoot
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    return process
}

private func waitForFiles(_ urls: [URL]) throws {
    let deadline = Date().addingTimeInterval(10)
    while !urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
        guard Date() < deadline else {
            throw QAFixtureStateError.invalidPersistedState(
                "timed out waiting for child-process fixture barrier"
            )
        }
        usleep(10_000)
    }
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
