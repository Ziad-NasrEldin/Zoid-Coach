import Darwin
import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
import ZoidCoachInfrastructure

private enum InjectedReminderListPolicyError: Error {
    case failed
}

private actor ReminderSnapshotSyncRecorder {
    private(set) var callCount = 0

    func record(_: [AgentReminderSnapshot]) {
        callCount += 1
    }
}

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
    _ = try PolicyStore(databaseURL: fixture.environment.databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
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
func appRefreshRetainsAnIncompleteLocalStarterPlanWhenExternalReminderListsAreFiltered() async throws {
    let fixture = try signedQARuntime("local-starter-plan-retention")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeControl(.init(
        requestID: "seed-empty-reminders",
        operation: .seed,
        seed: .init(permissions: [.reminders: .granted])
    ), runtime: fixture.environment)
    _ = try PolicyStore(databaseURL: fixture.environment.databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: TimeZone.current.identifier))
    let taskID = "zoid-local:onboarding:starter"
    let reminders = try ReminderSnapshotStore(databaseURL: fixture.environment.databaseURL)
    _ = try reminders.upsertLocal(ReminderSourceSnapshot(
        id: taskID,
        title: "Choose today's main objective",
        dueDate: nil,
        priority: 0,
        listID: "zoid-local",
        listName: "Zoid 666",
        sourceKind: .local
    ))
    let proposal = DailyPlanProposal(
        items: [PlannedTask(
            taskID: taskID,
            title: "Choose today's main objective",
            rank: 1,
            estimateMinutes: 15,
            reason: "Local onboarding fallback",
            score: 1
        )],
        mainObjectiveTaskID: taskID,
        plannedFocusMinutes: 15,
        availableFocusMinutes: 60
    )
    let planStore = try AutonomousPlanStore(databaseURL: fixture.environment.databaseURL)
    try planStore.replaceDailyPlan(proposal, for: Date())

    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        ),
        synchronizeReminderSnapshots: { _ in }
    )
    await model.refreshQAFixtureState()
    while model.isLoadingDailyPlan || model.isLoadingReminderTasks {
        await Task.yield()
    }

    #expect(model.reminderTasks.isEmpty)
    #expect(model.dailyPlan.map(\.reminderID) == [taskID])
    #expect(try planStore.loadDailyPlan(for: Date()).map(\.reminderID) == [taskID])
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

@MainActor
@Test
func qaReminderListDiscoveryUsesStableIdentifiersAndCurrentVisibleNames() async throws {
    let fixture = try signedQARuntime("reminder-list-discovery")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(
        permissions: [.reminders: .granted],
        reminderLists: [
            QAFixtureReminderList(id: "  list-work  ", name: "Work"),
            QAFixtureReminderList(id: "list-empty", name: "Empty List"),
        ],
        reminders: [
            SourceTask(id: "rename-task", title: "Task", listIdentifier: "  list-work  ", priority: 1, dueDate: nil, notes: nil, isCompleted: false)
        ]
    ))
    let service = QAFixtureRemindersService(adapter: adapter)

    #expect(await service.discoverLists() == .available([
        ReminderListChoice(id: "list-empty", name: "Empty List"),
        ReminderListChoice(id: "  list-work  ", name: "Work"),
    ]))

    try adapter.reset(to: .init(
        permissions: [.reminders: .granted],
        reminderLists: [
            QAFixtureReminderList(id: "  list-work  ", name: "Renamed Work"),
        ],
        reminders: [
            SourceTask(id: "rename-task", title: "Task", listIdentifier: "  list-work  ", priority: 1, dueDate: nil, notes: nil, isCompleted: false)
        ]
    ))

    #expect(await service.discoverLists() == .available([
        ReminderListChoice(id: "  list-work  ", name: "Renamed Work"),
    ]))
    guard case let .available(tasks) = await service.fetchIncompleteTasks() else {
        Issue.record("Expected QA Reminder tasks")
        return
    }
    #expect(tasks.map(\.listID) == ["  list-work  "])
    #expect(tasks.map(\.listName) == ["Renamed Work"])
}

@Test
func duplicateQAListIdentifiersReturnTypedValidationErrorWithoutCrashing() throws {
    let fixture = try signedQARuntime("duplicate-reminder-lists")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeControl(
        .init(
            requestID: "seed-duplicate-reminder-lists",
            operation: .seed,
            seed: .init(reminderLists: [
                QAFixtureReminderList(id: "duplicate", name: "First"),
                QAFixtureReminderList(id: "duplicate", name: "Second"),
            ])
        ),
        runtime: fixture.environment
    )

    #expect(throws: QAFixtureStateError.invalidPersistedState("invalid reminder lists")) {
        try QAFixtureOSComposition.makeAuthorizedAdapter(
            runtimeEnvironment: fixture.environment,
            clock: .fixed(fixture.now)
        )
    }
}

@MainActor
@Test
func appRefreshUsesExactReminderListPolicyAndExcludesUnknownLists() async throws {
    let fixture = try signedQARuntime("app-reminder-list-policy")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let opaqueID = "  list-work  "
    try writeControl(
        .init(
            requestID: "seed-app-reminder-list-policy",
            operation: .seed,
            seed: .init(
                permissions: [.reminders: .granted],
                reminderLists: [
                    QAFixtureReminderList(id: opaqueID, name: "Renamed Work"),
                    QAFixtureReminderList(id: "personal", name: "Personal"),
                    QAFixtureReminderList(id: "new-list", name: "New List"),
                ],
                reminders: [
                    SourceTask(id: "included", title: "Included", listIdentifier: opaqueID, priority: 1, dueDate: nil, notes: nil, isCompleted: false),
                    SourceTask(id: "excluded", title: "Excluded", listIdentifier: "personal", priority: 1, dueDate: nil, notes: nil, isCompleted: false),
                    SourceTask(id: "unknown", title: "Unknown", listIdentifier: "new-list", priority: 1, dueDate: nil, notes: nil, isCompleted: false),
                ]
            )
        ),
        runtime: fixture.environment
    )
    let policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        .replacingReminderListPolicy(ReminderListPolicy(
            isConfigured: true,
            decisions: [
                ReminderListDecision(listID: opaqueID, isIncluded: true),
                ReminderListDecision(listID: "personal", isIncluded: false),
            ]
        ))
    _ = try PolicyStore(databaseURL: fixture.environment.databaseURL)
        .saveSystemMaintenancePolicy(policy)
    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        )
    )

    await model.refreshQAFixtureState()

    #expect(model.reminderTasks.map(\.id) == ["included"])
    #expect(model.reminderTasks.first?.listID == opaqueID)
}

@MainActor
@Test
func appFailsClosedWhenReminderListPolicyCannotBeVerified() async throws {
    let fixture = try signedQARuntime("app-list-policy-failure")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeControl(
        .init(
            requestID: "seed-app-list-policy-failure",
            operation: .seed,
            seed: .init(
                permissions: [.reminders: .granted],
                reminders: [
                    SourceTask(id: "must-not-leak", title: "Hidden", listIdentifier: "private", priority: 1, dueDate: nil, notes: nil, isCompleted: false)
                ]
            )
        ),
        runtime: fixture.environment
    )
    let reminderStore = try ReminderSnapshotStore(
        databaseURL: fixture.environment.databaseURL
    )
    _ = try reminderStore.synchronize([
        ReminderSourceSnapshot(
            id: "durable-existing",
            title: "Existing durable import",
            dueDate: nil,
            priority: 1,
            listID: "private"
        )
    ])
    let syncRecorder = ReminderSnapshotSyncRecorder()
    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        ),
        reminderListPolicyLoader: { throw InjectedReminderListPolicyError.failed },
        synchronizeReminderSnapshots: { await syncRecorder.record($0) }
    )

    await model.refreshQAFixtureState()

    #expect(model.reminderTasks.isEmpty)
    #expect(!model.isLoadingReminderTasks)
    #expect(model.reminderTaskError?.contains("could not be verified") == true)
    #expect(await syncRecorder.callCount == 0)
    #expect(try reminderStore.loadIncomplete().map(\.id) == ["durable-existing"])
}

@MainActor
@Test
func settingsSaveImmediatelyRemovesExcludedReminderFromCurrentAppSession() async throws {
    let fixture = try signedQARuntime("settings-list-refresh")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeControl(
        .init(
            requestID: "seed-settings-list-refresh",
            operation: .seed,
            seed: .init(
                permissions: [.reminders: .granted],
                reminderLists: [
                    QAFixtureReminderList(id: "work", name: "Work"),
                    QAFixtureReminderList(id: "personal", name: "Personal"),
                ],
                reminders: [
                    SourceTask(id: "work-task", title: "Work", listIdentifier: "work", priority: 1, dueDate: nil, notes: nil, isCompleted: false),
                    SourceTask(id: "personal-task", title: "Personal", listIdentifier: "personal", priority: 1, dueDate: nil, notes: nil, isCompleted: false),
                ]
            )
        ),
        runtime: fixture.environment
    )
    let store = try PolicyStore(databaseURL: fixture.environment.databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let model = AppModel(
        runtimeEnvironment: fixture.environment,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: fixture.environment,
            service: NoopAgentRegistration()
        )
    )
    await model.refreshQAFixtureState()
    #expect(Set(model.reminderTasks.map(\.id)) == ["work-task", "personal-task"])
    let controller = SettingsPolicyController(
        databaseURL: fixture.environment.databaseURL,
        runtimeEnvironment: fixture.environment,
        savePolicyThroughAgent: { request in
            let receipt = try store.saveMutation(request)
            return AgentMutationReceipt(
                accepted: true,
                message: "saved",
                policyVersion: receipt.resultingVersion,
                policyMutationReceipt: receipt
            )
        },
        discoverReminderLists: {
            .available([
                ReminderListChoice(id: "work", name: "Work"),
                ReminderListChoice(id: "personal", name: "Personal"),
            ])
        },
        onReminderListPolicySaved: {
            model.refreshReminderTasks()
        }
    )
    controller.setReminderListDecision(true, listID: "work")
    controller.setReminderListDecision(false, listID: "personal")

    await controller.save()?.value
    while model.isLoadingReminderTasks { await Task.yield() }

    #expect(model.reminderTasks.map(\.id) == ["work-task"])
    #expect(!controller.hasUnsavedChanges)
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
        .wakeIntervention: [],
        .onboardingTest: [.continueIntentionally, .ignore]
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
func signedQACompositionAcceptsOnlyThePlatformTmpAlias() throws {
    let token = "zoid-signed-tmp-\(UUID().uuidString)"
    let aliasRoot = URL(fileURLWithPath: "/tmp/\(token)/run", isDirectory: true)
    let canonicalContainer = URL(
        fileURLWithPath: "/private/tmp/\(token)",
        isDirectory: true
    )
    let canonicalRoot = canonicalContainer.appendingPathComponent("run", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: canonicalContainer) }
    try FileManager.default.createDirectory(
        at: canonicalRoot,
        withIntermediateDirectories: true
    )
    let environment = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: aliasRoot,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let composition = try QAFixtureOSComposition.makeAuthorizedComposition(
        runtimeEnvironment: environment,
        clock: .fixed(Date(timeIntervalSince1970: 1_735_732_800))
    )

    #expect(environment.mode == .qa(runRoot: canonicalRoot))
    #expect(composition.adapter.stateFileURL.path.hasPrefix(canonicalRoot.path + "/"))
    #expect(FileManager.default.fileExists(atPath: composition.adapter.stateFileURL.path))
}

@Test
func signedQACompositionStillRejectsArbitraryTmpRootSymlink() throws {
    let token = "zoid-signed-tmp-symlink-\(UUID().uuidString)"
    let aliasRoot = URL(fileURLWithPath: "/tmp/\(token)/run", isDirectory: true)
    let canonicalContainer = URL(
        fileURLWithPath: "/private/tmp/\(token)",
        isDirectory: true
    )
    let canonicalRoot = canonicalContainer.appendingPathComponent("run", isDirectory: true)
    let outside = canonicalContainer.appendingPathComponent("outside", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: canonicalContainer) }
    let environment = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: aliasRoot,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    #expect(environment.mode == .qa(runRoot: canonicalRoot))
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: canonicalRoot, withDestinationURL: outside)

    #expect(throws: QAFixtureStateError.unsafeFilesystemEntry("run")) {
        try QAFixtureOSComposition.makeAuthorizedComposition(
            runtimeEnvironment: environment,
            clock: .fixed(Date(timeIntervalSince1970: 1_735_732_800))
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
    process.executableURL = try activeSwiftPMTestingHelper()
    guard let bundleExecutable = Bundle(for: FixtureTestBundleMarker.self).executableURL?.path else {
        throw QAFixtureStateError.invalidPersistedState(
            "the active Swift test bundle executable could not be resolved"
        )
    }
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

private final class FixtureTestBundleMarker {}

private func activeSwiftPMTestingHelper() throws -> URL {
    let lookup = Process()
    let output = Pipe()
    lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    lookup.arguments = ["--find", "swiftc"]
    lookup.standardOutput = output
    lookup.standardError = Pipe()
    try lookup.run()
    lookup.waitUntilExit()
    guard lookup.terminationStatus == 0 else {
        throw QAFixtureStateError.invalidPersistedState(
            "the active Swift compiler could not be resolved through xcrun"
        )
    }
    let swiftCompilerPath = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let toolchainUSR = URL(fileURLWithPath: swiftCompilerPath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let helper = toolchainUSR.appendingPathComponent(
        "libexec/swift/pm/swiftpm-testing-helper"
    )
    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
        throw QAFixtureStateError.invalidPersistedState(
            "swiftpm-testing-helper is unavailable in the active Swift toolchain"
        )
    }
    return helper
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
