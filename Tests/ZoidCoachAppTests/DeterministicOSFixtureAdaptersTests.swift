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
    #expect(try restarted.snapshot().audit.count == 3)

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
    #expect(try adapters.snapshot().audit.contains { $0.outcome.hasPrefix("refused:") })
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
    #expect(try restarted.snapshot().notifications.first?.status == .responded)
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
    #expect(try adapters.snapshot().audit.last?.timestamp == fixture.now)
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
    #expect(try recovered.permission(.calendar) == .granted)
    #expect(try recovered.snapshot().audit.map(\.operation) == ["recover-corrupt-state"])
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
func osFixturesRefuseIntermediateFixturesSymlinkBeforeInitialization() throws {
    let fixture = try makeOSFixture("ancestor-symlink")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let fixtures = fixture.workspace.root.deletingLastPathComponent()
    let outside = fixture.container.appendingPathComponent("outside-fixtures", isDirectory: true)
    try FileManager.default.moveItem(at: fixtures, to: outside)
    try FileManager.default.createSymbolicLink(at: fixtures, withDestinationURL: outside)

    #expect(throws: QAFixtureStateError.unsafeFilesystemEntry("Fixtures")) {
        try fixture.adapters(seed: .init())
    }
    #expect(!FileManager.default.fileExists(
        atPath: outside.appendingPathComponent("ancestor-symlink/OS Fixtures").path
    ))
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
    #expect(try resumed.permission(.calendar) == .granted)
    #expect(try resumed.snapshot().audit.map(\.operation) == ["recover-corrupt-state"])
    #expect(!FileManager.default.fileExists(
        atPath: first.stateFileURL.deletingLastPathComponent().appendingPathComponent("recovery.json").path
    ))
}

@Test
func osFixtureRejectsMalformedRecoveryMarker() throws {
    let fixture = try makeOSFixture("malformed-recovery")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let directory = fixture.workspace.root.appendingPathComponent("OS Fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("malformed".utf8).write(to: directory.appendingPathComponent("recovery.json"))

    #expect(throws: QAFixtureStateError.corruptState(
        path: directory.appendingPathComponent("state.json").path
    )) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRecoveryResumesFromReplacementWrittenPhaseWithoutDuplicateAudit() throws {
    let fixture = try makeOSFixture("replacement-written")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let first = try fixture.adapters(seed: .init())
    try Data("corrupt".utf8).write(to: first.stateFileURL, options: .atomic)

    #expect(throws: FixtureInterruption.afterReplacement) {
        try fixture.adapters(
            seed: .init(),
            recovery: .reset(.init(permissions: [.calendar: .granted])),
            storageCheckpoint: { checkpoint in
                if case .replacementStatePersisted = checkpoint {
                    throw FixtureInterruption.afterReplacement
                }
            }
        )
    }

    let resumed = try fixture.adapters(seed: .init())
    #expect(try resumed.permission(.calendar) == .granted)
    #expect(try resumed.snapshot().audit.map(\.operation) == ["recover-corrupt-state"])
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
    #expect(try restarted.snapshot().audit.isEmpty)
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
    #expect(Set(try restarted.snapshot().audit.map(\.id)).count == 24)
}

@Test
func osFixtureCoordinatesTwoInstancesWithoutLostActionsOrReusedIDs() async throws {
    let fixture = try makeOSFixture("two-instances")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let permissions: [QAFixturePermission: QAFixturePermissionState] = [
        .reminders: .granted,
        .notifications: .granted
    ]
    let first = try fixture.adapters(seed: .init(permissions: permissions))
    let second = try fixture.adapters(seed: .init())

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0 ..< 40 {
            let adapter = index.isMultiple(of: 2) ? first : second
            group.addTask {
                _ = try await adapter.create(
                    title: "Shared \(index)", dueDate: nil,
                    listIdentifier: nil, metadataMarker: "shared-\(index)"
                )
            }
        }
        try await group.waitForAll()
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0 ..< 10 {
            let adapter = index.isMultiple(of: 2) ? second : first
            group.addTask {
                _ = try await adapter.schedule(.init(
                    category: "coach", title: "N\(index)", body: "Body",
                    promptID: "prompt-\(index)"
                ))
            }
        }
        try await group.waitForAll()
    }

    #expect(try first.allReminders().count == 40)
    #expect(try second.allReminders().count == 40)
    let snapshot = try first.snapshot()
    #expect(snapshot.notifications.count == 10)
    #expect(snapshot.audit.count == 50)
    #expect(Set(snapshot.reminders.map(\.id)) == Set((0 ..< 40).map { "qa-reminder-\($0)" }))
    #expect(snapshot.audit.map(\.id) == (0 ..< 50).map { "qa-audit-\($0)" })
    let object = try persistedJSONObject(first.stateFileURL)
    #expect(try persistedCounter(.reminder, in: object) == 40)
    #expect(try persistedCounter(.notification, in: object) == 10)
    #expect(try persistedCounter(.audit, in: object) == 50)
}

@Test
func osFixtureWaitsForChildProcessAdvisoryLock() async throws {
    let fixture = try makeOSFixture("child-flock")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    let directory = adapters.stateFileURL.deletingLastPathComponent()
    let ready = fixture.container.appendingPathComponent("child-lock-ready")
    let release = fixture.container.appendingPathComponent("child-lock-release")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    child.arguments = [
        "-c",
        "import fcntl, os, pathlib, sys, time\nfd=os.open(sys.argv[1], os.O_RDONLY)\nfcntl.flock(fd, fcntl.LOCK_EX)\npathlib.Path(sys.argv[2]).write_text('ready')\nwhile not pathlib.Path(sys.argv[3]).exists(): time.sleep(0.01)\nfcntl.flock(fd, fcntl.LOCK_UN)\nos.close(fd)",
        directory.path, ready.path, release.path
    ]
    try child.run()
    defer { if child.isRunning { child.terminate() } }
    for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: ready.path) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(FileManager.default.fileExists(atPath: ready.path))
    let completion = CompletionFlag()
    let mutation = Task {
        _ = try await adapters.create(
            title: "After child", dueDate: nil,
            listIdentifier: nil, metadataMarker: nil
        )
        completion.markCompleted()
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(!completion.isCompleted)
    try Data("release".utf8).write(to: release)
    child.waitUntilExit()
    try await mutation.value
    #expect(completion.isCompleted)
    #expect(try adapters.allReminders().count == 1)
}

@Test
func osFixtureRejectsRegressedReminderCounterAtLoad() async throws {
    let fixture = try makeOSFixture("counter-reminder")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    _ = try await adapters.create(title: "One", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    try rewriteCounter(.reminder, value: 0, at: adapters.stateFileURL)
    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsRegressedCalendarCounterAtLoad() async throws {
    let fixture = try makeOSFixture("counter-calendar")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.calendar: .granted]))
    _ = try await adapters.apply(.createBlock(.init(
        title: "One", start: fixture.now,
        end: fixture.now.addingTimeInterval(600),
        ownershipToken: "one", planItemID: "one"
    )))
    try rewriteCounter(.calendarCommitment, value: 0, at: adapters.stateFileURL)
    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsRegressedNotificationCounterAtLoad() async throws {
    let fixture = try makeOSFixture("counter-notification")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.notifications: .granted]))
    _ = try await adapters.schedule(.init(
        category: "coach", title: "One", body: "One", promptID: "one"
    ))
    try rewriteCounter(.notification, value: 0, at: adapters.stateFileURL)
    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsRegressedAuditCounterAtLoad() throws {
    let fixture = try makeOSFixture("counter-audit")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init())
    try adapters.setPermission(.granted, for: .calendar)
    try rewriteCounter(.audit, value: 0, at: adapters.stateFileURL)
    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsReusedGeneratedCounterIndexAtLoad() async throws {
    let fixture = try makeOSFixture("counter-reused")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    _ = try await adapters.create(title: "One", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    var object = try persistedJSONObject(adapters.stateFileURL)
    var allocations = try #require(object["generatedIdentifiers"] as? [[String: Any]])
    allocations.append([
        "kind": "reminder", "index": 0, "id": "deleted-reminder",
        "provenance": "stableProvider"
    ])
    object["generatedIdentifiers"] = allocations
    if var counters = object["counters"] as? [String: Any] {
        counters[QAFixtureEntityKind.reminder.rawValue] = 2
        object["counters"] = counters
    } else {
        var counters = try #require(object["counters"] as? [Any])
        let index = try #require(counters.firstIndex(where: { ($0 as? String) == "reminder" }))
        counters[index + 1] = 2
        object["counters"] = counters
    }
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: adapters.stateFileURL, options: .atomic)

    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureDeleteOfAbsentOwnedBlockIsIdempotent() async throws {
    let fixture = try makeOSFixture("delete-absent")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.calendar: .granted]))

    let deleted = try await adapters.apply(.deleteOwnedBlock(identifier: "absent", ownershipToken: "owned"))

    #expect(deleted == nil)
    #expect(try adapters.snapshot().audit.last?.outcome == "succeeded")
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
func osFixtureRejectsCoherentlyTamperedStableProviderID() async throws {
    let fixture = try makeOSFixture("provider-tamper")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.reminders: .granted]))
    _ = try await adapters.create(title: "Original", dueDate: nil, listIdentifier: nil, metadataMarker: nil)
    var object = try persistedJSONObject(adapters.stateFileURL)
    var reminders = try #require(object["reminders"] as? [[String: Any]])
    reminders[0]["id"] = "forged-reminder"
    object["reminders"] = reminders
    var allocations = try #require(object["generatedIdentifiers"] as? [[String: Any]])
    let allocationIndex = try #require(
        allocations.firstIndex(where: { ($0["kind"] as? String) == "reminder" })
    )
    allocations[allocationIndex]["id"] = "forged-reminder"
    object["generatedIdentifiers"] = allocations
    try writePersistedJSONObject(object, to: adapters.stateFileURL)

    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsNotificationWithProviderProvenance() async throws {
    let fixture = try makeOSFixture("notification-provenance")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let adapters = try fixture.adapters(seed: .init(permissions: [.notifications: .granted]))
    _ = try await adapters.schedule(.init(
        category: "coach", title: "One", body: "Body", promptID: "caller-one"
    ))
    var object = try persistedJSONObject(adapters.stateFileURL)
    var allocations = try #require(object["generatedIdentifiers"] as? [[String: Any]])
    let allocationIndex = try #require(
        allocations.firstIndex(where: { ($0["kind"] as? String) == "notification" })
    )
    allocations[allocationIndex]["provenance"] = "stableProvider"
    object["generatedIdentifiers"] = allocations
    try writePersistedJSONObject(object, to: adapters.stateFileURL)

    #expect(throws: QAFixtureStateError.corruptState(path: adapters.stateFileURL.path)) {
        try fixture.adapters(seed: .init())
    }
}

@Test
func osFixtureRejectsUnsupportedReminderPrioritySeed() throws {
    let fixture = try makeOSFixture("invalid-reminder-seed")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let invalid = SourceTask(
        id: "seed", title: "Invalid", listIdentifier: "inbox", priority: 3,
        dueDate: nil, notes: nil, isCompleted: false
    )
    #expect(throws: QAFixtureStateError.self) {
        try fixture.adapters(seed: .init(reminders: [invalid]))
    }
}

@Test
func osFixtureRejectsInvalidCalendarRangeSeed() throws {
    let fixture = try makeOSFixture("invalid-calendar-seed")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let invalid = CalendarCommitment(
        id: "seed", title: "Invalid", start: fixture.now, end: fixture.now,
        calendarIdentifier: "work"
    )
    #expect(throws: QAFixtureStateError.self) {
        try fixture.adapters(seed: .init(calendarCommitments: [invalid]))
    }
}

@Test
func osFixtureRejectsDeliveryBeforeRequestedDateSeed() throws {
    let fixture = try makeOSFixture("invalid-delivery-seed")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let invalid = QAFixtureNotificationRecord(
        id: "prompt", desired: .init(
            category: "coach", title: "Prompt", body: "Body", promptID: "prompt",
            deliveryDate: fixture.now.addingTimeInterval(60)
        ),
        status: .delivered, deliveredAt: fixture.now
    )
    #expect(throws: QAFixtureStateError.self) {
        try fixture.adapters(seed: .init(notifications: [invalid]))
    }
}

@Test
func osFixtureRejectsResponseBeforeDeliverySeed() throws {
    let fixture = try makeOSFixture("invalid-response-seed")
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let invalid = QAFixtureNotificationRecord(
        id: "prompt", desired: .init(
            category: "coach", title: "Prompt", body: "Body", promptID: "prompt"
        ),
        status: .responded, deliveredAt: fixture.now,
        actionIdentifier: "resume",
        respondedAt: fixture.now.addingTimeInterval(-1)
    )
    #expect(throws: QAFixtureStateError.self) {
        try fixture.adapters(seed: .init(notifications: [invalid]))
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
    case afterReplacement
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

private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func markCompleted() { lock.withLock { completed = true } }
    var isCompleted: Bool { lock.withLock { completed } }
}

private func persistedJSONObject(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func writePersistedJSONObject(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: url, options: .atomic)
}

private func persistedCounter(
    _ kind: QAFixtureEntityKind,
    in object: [String: Any]
) throws -> Int {
    if let counters = object["counters"] as? [String: Any] {
        return try #require(counters[kind.rawValue] as? Int)
    }
    let counters = try #require(object["counters"] as? [Any])
    let index = try #require(
        counters.firstIndex(where: { ($0 as? String) == kind.rawValue })
    )
    return try #require(counters[index + 1] as? Int)
}

private func rewriteCounter(
    _ kind: QAFixtureEntityKind,
    value: Int,
    at url: URL
) throws {
    var object = try persistedJSONObject(url)
    if var counters = object["counters"] as? [String: Any] {
        counters[kind.rawValue] = value
        object["counters"] = counters
    } else {
        var counters = try #require(object["counters"] as? [Any])
        let index = try #require(
            counters.firstIndex(where: { ($0 as? String) == kind.rawValue })
        )
        counters[index + 1] = value
        object["counters"] = counters
    }
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: url, options: .atomic)
}

private func makeOSFixture(_ label: String) throws -> OSFixtureHarness {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let container = repositoryRoot
        .appendingPathComponent(".build/os-fixture-tests", isDirectory: true)
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
