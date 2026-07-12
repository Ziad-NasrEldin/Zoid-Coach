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
    try adapters.syncExternalCalendarCommitments([
        CalendarCommitment(id: "b", title: "B", start: fixture.now, end: fixture.now.addingTimeInterval(600), calendarIdentifier: "work"),
        CalendarCommitment(id: "a", title: "A", start: fixture.now, end: fixture.now.addingTimeInterval(600), calendarIdentifier: "work")
    ])
    let ordered = try await adapters.commitments(
        from: fixture.now.addingTimeInterval(-1),
        through: fixture.now.addingTimeInterval(601),
        calendarIdentifiers: ["work"]
    )
    #expect(ordered.map(\.id) == ["a", "b"])
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
func osFixtureNotificationOperationUsesOneClockInstant() throws {
    let fixture = try makeOSFixture("one-notification-instant")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let sequence = TimestampSequence(start: fixture.now)
    let notifications = ["one", "two"].map { identifier in
        QAFixtureNotificationRecord(
            id: identifier,
            desired: .init(
                category: "coach", title: identifier, body: identifier,
                promptID: identifier
            )
        )
    }
    let adapters = try DeterministicOSFixtureAdapters(
        workspace: fixture.workspace,
        seed: .init(
            permissions: [.notifications: .granted],
            notifications: notifications
        ),
        clock: .init(now: { sequence.next() }),
        stableID: { kind, index in "qa-\(kind.rawValue)-\(index)" }
    )

    let delivered = try adapters.deliverDueNotifications()

    #expect(delivered.allSatisfy { $0.deliveredAt == fixture.now })
    #expect(adapters.snapshot().audit.last?.timestamp == fixture.now)
    #expect(sequence.callCount == 1)
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

    #expect(throws: QAFixtureStateError.unsafeFilesystemEntry("OS Fixtures")) {
        try fixture.adapters(seed: .init())
    }
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("state.json").path))
}

@Test
func osFixturesRefuseReplacedWorkspaceRootSymlink() throws {
    let fixture = try makeOSFixture("root-symlink")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let original = fixture.workspace.root
    let preserved = original.deletingLastPathComponent().appendingPathComponent("preserved-root")
    let outside = fixture.container.appendingPathComponent("outside-root", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: preserved)
    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)

    #expect(throws: QAFixtureStateError.unsafeFilesystemEntry("root-symlink")) {
        try fixture.adapters(seed: .init())
    }
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("OS Fixtures").path))
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

    #expect(throws: QAFixtureStateError.unsafeFilesystemEntry("state.json")) {
        try fixture.adapters(seed: .init())
    }
    #expect(try Data(contentsOf: outside) == Data("{}".utf8))
}

@Test
func osFixtureDescriptorRemainsContainedAfterParentReplacement() async throws {
    let fixture = try makeOSFixture("parent-replacement")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    let original = fixture.workspace.root.appendingPathComponent("OS Fixtures", isDirectory: true)
    let pinned = fixture.workspace.root.appendingPathComponent("Pinned Fixtures", isDirectory: true)
    let outside = fixture.container.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: pinned)
    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)

    _ = try await adapters.create(title: "Pinned", dueDate: nil, listIdentifier: nil, metadataMarker: nil)

    #expect(FileManager.default.fileExists(atPath: pinned.appendingPathComponent("state.json").path))
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("state.json").path))
}

@Test
func osFixtureRecoveryResumesAfterQuarantineInterruption() throws {
    let fixture = try makeOSFixture("recovery-resume")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let first = try fixture.adapters(seed: .init())
    try Data("corrupt".utf8).write(to: first.stateFileURL, options: .atomic)

    #expect(throws: FixtureInterruption.afterQuarantine) {
        try fixture.adapters(
            seed: .init(),
            recovery: .reset(.init(permissions: [.calendar: .granted])),
            storageCheckpoint: { checkpoint in
                if case .corruptStateQuarantined = checkpoint {
                    throw FixtureInterruption.afterQuarantine
                }
            }
        )
    }

    let resumed = try fixture.adapters(seed: .init())
    #expect(resumed.permission(.calendar) == .granted)
    #expect(resumed.snapshot().audit.map(\.operation) == ["recover-corrupt-state"])
    #expect(!FileManager.default.fileExists(
        atPath: first.stateFileURL.deletingLastPathComponent().appendingPathComponent("recovery.json").path
    ))
}

@Test
func osFixtureWriteFailureDoesNotPublishPartialMutation() async throws {
    let fixture = try makeOSFixture("write-failure")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    _ = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    let failing = try fixture.adapters(
        seed: .init(),
        storageCheckpoint: { checkpoint in
            if case .beforeStateCommit = checkpoint { throw FixtureInterruption.beforeCommit }
        }
    )

    await #expect(throws: FixtureInterruption.beforeCommit) {
        try await failing.create(title: "Not committed", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    }

    let restarted = try fixture.adapters(seed: .init())
    #expect(try restarted.allReminders().isEmpty)
    #expect(restarted.snapshot().audit.isEmpty)
}

@Test
func osFixtureSerializesConcurrentMutationsWithUniquePersistentIDs() async throws {
    let fixture = try makeOSFixture("concurrent")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))

    try await withThrowingTaskGroup(of: SourceTask.self) { group in
        for index in 0 ..< 24 {
            group.addTask {
                try await adapters.create(
                    title: "Task \(index)", dueDate: nil,
                    listIdentifier: nil, metadataMarker: "task-\(index)"
                )
            }
        }
        var identifiers: Set<String> = []
        for try await task in group { identifiers.insert(task.id) }
        #expect(identifiers.count == 24)
    }

    let restarted = try fixture.adapters(seed: .init())
    #expect(try restarted.allReminders().count == 24)
    #expect(Set(restarted.snapshot().audit.map(\.id)).count == 24)
}

@Test
func osFixtureDeleteOfAbsentOwnedBlockIsIdempotent() async throws {
    let fixture = try makeOSFixture("delete-absent")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.calendar: .granted]))

    let deleted = try await adapters.apply(.deleteOwnedBlock(identifier: "absent", ownershipToken: "owned"))

    #expect(deleted == nil)
    #expect(adapters.snapshot().audit.last?.outcome == "succeeded")
}

@Test
func osFixtureRejectsInvalidPersistedAuditAndCounterState() throws {
    let fixture = try makeOSFixture("persisted-validation")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init())
    try adapters.setPermission(.granted, for: .calendar)
    var object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: adapters.stateFileURL)) as? [String: Any]
    )
    var audit = try #require(object["audit"] as? [[String: Any]])
    audit[0]["id"] = ""
    object["audit"] = audit
    if var counters = object["counters"] as? [String: Any] {
        counters["audit"] = -1
        object["counters"] = counters
    } else if var counters = object["counters"] as? [Any] {
        if let index = counters.firstIndex(where: { ($0 as? String) == "audit" }), index + 1 < counters.count {
            counters[index + 1] = -1
        }
        object["counters"] = counters
    }
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: adapters.stateFileURL, options: .atomic)

    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
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
        recovery: QAFixtureCorruptionRecovery = .fail,
        storageCheckpoint: @escaping @Sendable (QAFixtureStorageCheckpoint) throws -> Void = { _ in }
    ) throws -> DeterministicOSFixtureAdapters {
        try DeterministicOSFixtureAdapters(
            workspace: workspace,
            seed: seed,
            clock: .fixed(now),
            stableID: { kind, index in "qa-\(kind.rawValue)-\(index)" },
            corruptionRecovery: recovery,
            storageCheckpoint: storageCheckpoint
        )
    }
}

private enum FixtureInterruption: Error {
    case beforeCommit
    case afterQuarantine
}

private final class TimestampSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let start: Date
    private var calls = 0

    init(start: Date) { self.start = start }

    func next() -> Date {
        lock.withLock {
            defer { calls += 1 }
            return start.addingTimeInterval(TimeInterval(calls))
        }
    }

    var callCount: Int { lock.withLock { calls } }
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
