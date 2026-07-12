import Foundation
import Testing
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func osFixturesPersistReminderMutationsAcrossRestartAndReset() async throws {
    let fixture = try makeOSFixture("restart")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let seedTask = task(id: "seed-reminder", title: "Seed")
    let seed = QAFixtureOSSeed(
        permissions: [.reminders: .granted],
        reminders: [seedTask]
    )
    let first = try fixture.adapters(seed: seed)

    let created = try await first.create(
        title: "Write review", dueDate: fixture.now, listIdentifier: nil,
        metadataMarker: "plan-1"
    )
    _ = try await first.apply(.setPriority(5), to: created.id)
    _ = try await first.apply(.complete(at: fixture.now), to: created.id)

    let restarted = try fixture.adapters(seed: .init())
    let persisted = try await restarted.task(identifier: created.id)
    #expect(persisted?.priority == 5)
    #expect(persisted?.isCompleted == true)
    #expect(restarted.snapshot().audit.count == 3)

    try restarted.reset(to: seed)
    #expect(try restarted.allReminders() == [seedTask])
}

@Test
func osFixturesRepresentEveryPermissionStateAndAuditRefusals() async throws {
    let fixture = try makeOSFixture("permissions")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .denied]))

    await #expect(throws: ActionSourceError.accessDenied) {
        try await adapters.task(identifier: "missing")
    }
    try adapters.setPermission(.restricted, for: .reminders)
    await #expect(throws: ActionSourceError.accessDenied) {
        try await adapters.create(title: "No", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    }
    try adapters.setPermission(.notDetermined, for: .reminders)
    await #expect(throws: ActionSourceError.temporarilyUnavailable) {
        try await adapters.create(title: "Wait", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    }
    try adapters.setPermission(.granted, for: .reminders)
    #expect(try await adapters.create(title: "Yes", dueDate: nil, listIdentifier: nil, metadataMarker: nil).title == "Yes")
    let synced = task(id: "synced-reminder", title: "Synced")
    try adapters.syncReminders([synced])
    #expect(try adapters.allReminders() == [synced])
    #expect(throws: QAFixtureStateError.duplicateIdentifier("synced-reminder")) {
        try adapters.syncReminders([synced, synced])
    }
    #expect(try adapters.allReminders() == [synced])
    #expect(adapters.snapshot().audit.contains { $0.outcome.hasPrefix("refused:") })
}

@Test
func osFixturesPreserveOwnedBlocksAndRefuseExternalCalendarMutation() async throws {
    let fixture = try makeOSFixture("calendar")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let external = CalendarCommitment(
        id: "external-1", title: "Client call", start: fixture.now,
        end: fixture.now.addingTimeInterval(1_800), calendarIdentifier: "work"
    )
    let adapters = try fixture.adapters(seed: .init(
        permissions: [.calendar: .granted], calendarCommitments: [external]
    ))

    let owned = try #require(try await adapters.apply(.createBlock(.init(
        title: "Focus", start: fixture.now.addingTimeInterval(3_600),
        end: fixture.now.addingTimeInterval(7_200), ownershipToken: "owned-1",
        planItemID: "plan-1"
    ))))
    await #expect(throws: ActionSourceError.ownershipViolation) {
        try await adapters.apply(.deleteOwnedBlock(identifier: external.id, ownershipToken: "not-owned"))
    }
    try adapters.syncExternalCalendarCommitments([
        CalendarCommitment(
            id: "external-2", title: "Updated feed", start: fixture.now,
            end: fixture.now.addingTimeInterval(900), calendarIdentifier: "work"
        )
    ])
    #expect(try await adapters.ownedCommitment(ownershipToken: "owned-1")?.id == owned.id)
    #expect(try await adapters.commitment(identifier: external.id) == nil)
}

@Test
func osFixturesDeliverAndRespondToNotificationsEndToEnd() async throws {
    let fixture = try makeOSFixture("notifications")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.notifications: .granted]))
    let id = try await adapters.schedule(.init(
        category: "coach", title: "Resume", body: "Return to focus",
        promptID: "prompt-1", deliveryDate: fixture.now
    ))

    #expect(id == "prompt-1")
    #expect(try await adapters.pending(identifier: id))
    #expect(try adapters.deliverDueNotifications().map(\.id) == [id])
    #expect(!(try await adapters.pending(identifier: id)))
    let response = try adapters.respondToNotification(identifier: id, actionIdentifier: "resume")
    #expect(response.status == .responded)
    #expect(response.actionIdentifier == "resume")

    let restarted = try fixture.adapters(seed: .init())
    #expect(restarted.snapshot().notifications.first?.status == .responded)
}

@Test
func osFixturesFailClosedOnCorruptionAndRecoverInsideWorkspace() throws {
    let fixture = try makeOSFixture("corruption")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let first = try fixture.adapters(seed: .init())
    try Data("not-json".utf8).write(to: first.stateFileURL, options: .atomic)

    #expect(throws: QAFixtureStateError.corruptState(path: first.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
    let recovered = try fixture.adapters(
        seed: .init(), recovery: .reset(.init(permissions: [.calendar: .granted]))
    )
    #expect(recovered.permission(.calendar) == .granted)
    #expect(recovered.snapshot().audit.map(\.operation) == ["recover-corrupt-state"])
    #expect(FileManager.default.fileExists(atPath: recovered.corruptStateFileURL.path))
    #expect(recovered.corruptStateFileURL.path.hasPrefix(fixture.workspace.root.path + "/"))
}

@Test
func osFixturesRefuseSymlinkEscapeBeforeWriting() throws {
    let fixture = try makeOSFixture("containment")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let outside = fixture.container.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: fixture.workspace.root.appendingPathComponent("OS Fixtures"),
        withDestinationURL: outside
    )

    #expect(throws: QAFixtureStateError.stateOutsideWorkspace(path: outside.path)) {
        try fixture.adapters(seed: .init())
    }
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("state.json").path))
}

@Test
func osFixturesRefuseStateFileSymlinkEscapeBeforeReading() throws {
    let fixture = try makeOSFixture("state-symlink")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let outside = fixture.container.appendingPathComponent("outside-state.json")
    try Data("{}".utf8).write(to: outside)
    let directory = fixture.workspace.root.appendingPathComponent("OS Fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent("state.json"),
        withDestinationURL: outside
    )

    #expect(throws: QAFixtureStateError.stateOutsideWorkspace(path: outside.path)) {
        try fixture.adapters(seed: .init())
    }
    #expect(try Data(contentsOf: outside) == Data("{}".utf8))
}

@Test
func osFixtureAdapterHasNoProductionFrameworkOrAdapterDependency() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/ZoidCoachInfrastructure/DeterministicOSFixtureAdapters.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(!source.contains("import EventKit"))
    #expect(!source.contains("import UserNotifications"))
    #expect(!source.contains("EventKitTaskSource"))
    #expect(!source.contains("EventKitCalendarSource"))
    #expect(!source.contains("UserNotificationActionSource"))
}

private struct OSFixtureHarness {
    let container: URL
    let workspace: QAFixtureWorkspace
    let now: Date

    func adapters(
        seed: QAFixtureOSSeed,
        recovery: QAFixtureCorruptionRecovery = .fail
    ) throws -> DeterministicOSFixtureAdapters {
        try DeterministicOSFixtureAdapters(
            workspace: workspace,
            seed: seed,
            clock: .fixed(now),
            stableID: { kind, index in "qa-\(kind.rawValue)-\(index)" },
            corruptionRecovery: recovery
        )
    }
}

private func makeOSFixture(_ label: String) throws -> OSFixtureHarness {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-os-fixtures-\(label)-\(UUID().uuidString)", isDirectory: true)
    let environment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", container.appendingPathComponent("qa").path],
        processEnvironment: [:]
    ).environment
    let workspace = try QAFixtureWorkspaceBuilder(environment: environment)
        .prepare(fixtureID: label)
    return .init(
        container: container,
        workspace: workspace,
        now: Date(timeIntervalSince1970: 1_735_732_800)
    )
}

private func task(id: String, title: String) -> SourceTask {
    .init(
        id: id, title: title, listIdentifier: "inbox", priority: 0,
        dueDate: nil, notes: nil, isCompleted: false
    )
}
