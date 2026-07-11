import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func trippedDatabaseBreakerStopsExternalActionsBeforeClaimingOutboxWork() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .completeReminder,
        entityID: "reminder-1",
        desiredState: .completeReminder,
        date: date
    )])
    let tasks = FakeTaskSource(tasks: [SourceTask(
        id: "reminder-1", title: "One", listIdentifier: "work", priority: 0,
        dueDate: nil, notes: nil, isCompleted: false
    )])
    let breaker = DatabaseWriteCircuitBreaker()
    breaker.trip(reason: "sqlite_write_failed", at: date)
    let executor = ActionCommandExecutor(
        outbox: outbox, tasks: tasks, calendar: FakeCalendarSource(),
        writeCircuitBreaker: breaker, now: { date }
    )

    #expect(await executor.executeNext() == .outboxFailure(reason: "database_read_only"))
    #expect(await tasks.mutations.isEmpty)
}

@Test
func databaseBreakerTripsWhenExternalEffectSucceedsButOutboxFinalizationFails() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let task = SourceTask(id: "reminder-1", title: "One", listIdentifier: "work", priority: 0, dueDate: nil, notes: nil, isCompleted: false)
    let tasks = FakeTaskSource(tasks: [task])
    let outbox = FakeActionCommandQueue(
        commands: [makeCommand(type: .completeReminder, entityID: task.id, desiredState: .completeReminder, date: date)],
        failSuccessFinalization: true
    )
    let breaker = DatabaseWriteCircuitBreaker()
    let executor = ActionCommandExecutor(outbox: outbox, tasks: tasks, calendar: FakeCalendarSource(), writeCircuitBreaker: breaker, now: { date })

    #expect(await executor.executeNext() == .outboxFailure(reason: "outbox_finalize_failed"))
    #expect(breaker.snapshot.isTripped)
    #expect(await tasks.mutations == [.complete(at: date)])
    #expect(await executor.executeNext() == .outboxFailure(reason: "database_read_only"))
}

@Test
func calendarUpdateMutatesOnlyTheBlockWithTheCommandsOwnershipToken() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let foreign = CalendarCommitment(
        id: "foreign-event",
        title: "Someone else's block",
        start: date,
        end: date.addingTimeInterval(1_800),
        calendarIdentifier: "calendar",
        ownershipToken: "foreign-token"
    )
    let calendar = FakeCalendarSource(commitments: [foreign])
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .updateCalendarBlock,
        entityID: foreign.id,
        desiredState: .calendarBlock(CalendarBlockDesiredState(
            title: "Changed",
            start: date,
            end: date.addingTimeInterval(3_600),
            ownershipToken: "expected-token",
            planItemID: "plan-1"
        )),
        date: date
    )])
    let executor = ActionCommandExecutor(outbox: outbox, tasks: FakeTaskSource(), calendar: calendar, now: { date })

    let result = await executor.executeNext()

    #expect(result == .terminalFailure(commandID: "command-1", reason: "ownership_violation"))
    #expect(await calendar.mutations.isEmpty)
    #expect(await outbox.terminalFailures == ["command-1"])
}

@Test
func interruptedCalendarCreationRecoversTheExistingOwnedBlockWithoutDuplicatingIt() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = CalendarCommitment(
        id: "event-42",
        title: "Deep work",
        start: date,
        end: date.addingTimeInterval(3_600),
        calendarIdentifier: "zoid-calendar",
        ownershipToken: "zoid-token"
    )
    let command = makeCommand(
        type: .createCalendarBlock,
        entityID: "plan-42",
        desiredState: .calendarBlock(CalendarBlockDesiredState(
            title: existing.title,
            start: existing.start,
            end: existing.end,
            ownershipToken: "zoid-token",
            planItemID: "plan-42"
        )),
        state: .executing,
        attemptCount: 1,
        date: date
    )
    let outbox = FakeActionCommandQueue(executing: [command])
    let calendar = FakeCalendarSource(commitments: [existing])
    let executor = ActionCommandExecutor(outbox: outbox, tasks: FakeTaskSource(), calendar: calendar, now: { date })

    let result = await executor.executeNext()

    #expect(result == .reconciled(commandIDs: ["command-1"]))
    #expect(await outbox.successes == ["command-1"])
    #expect(await calendar.mutations.isEmpty)
}

@Test
func confirmedMeetingUsesFingerprintLookupForExactOnceRecovery() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = CalendarCommitment(
        id: "meeting-event",
        title: "Project review",
        start: date,
        end: date.addingTimeInterval(2_700),
        calendarIdentifier: "calendar",
        meetingFingerprint: "chat-fingerprint"
    )
    let command = makeCommand(
        type: .createConfirmedMeeting,
        entityID: "candidate-1",
        desiredState: .meeting(MeetingDesiredState(
            title: existing.title,
            start: existing.start,
            durationMinutes: 45,
            calendarIdentifier: nil,
            candidateFingerprint: "chat-fingerprint"
        )),
        date: date
    )
    let outbox = FakeActionCommandQueue(commands: [command])
    let calendar = FakeCalendarSource(commitments: [existing])
    let executor = ActionCommandExecutor(outbox: outbox, tasks: FakeTaskSource(), calendar: calendar, now: { date })

    let result = await executor.executeNext()

    #expect(result == .succeeded(commandID: "command-1", platformIdentifier: "meeting-event"))
    #expect(await calendar.mutations.isEmpty)
}

@Test
func meetingDesiredStateDecodesCommandsWrittenBeforeFidelityFieldsExisted() throws {
    let legacy = Data(#"{"title":"Legacy meeting","start":0,"durationMinutes":30,"calendarIdentifier":null,"candidateFingerprint":"legacy-fingerprint"}"#.utf8)

    let decoded = try JSONDecoder().decode(MeetingDesiredState.self, from: legacy)

    #expect(decoded.title == "Legacy meeting")
    #expect(decoded.participants.isEmpty)
    #expect(decoded.location == nil)
    #expect(decoded.callLink == nil)
    #expect(decoded.timezoneIdentifier == nil)
}

@Test
func confirmedMeetingPropagatesCapturedContextToCalendarMutation() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let desired = MeetingDesiredState(
        title: "Planning review",
        start: date,
        durationMinutes: 45,
        calendarIdentifier: "work",
        candidateFingerprint: "context-fingerprint",
        participants: ["Alex", "Noor"],
        location: "Studio 2",
        callLink: "https://meet.example.test/room",
        timezoneIdentifier: "Africa/Cairo"
    )
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .createConfirmedMeeting,
        entityID: "candidate-context",
        desiredState: .meeting(desired),
        date: date
    )])
    let calendar = FakeCalendarSource()
    let executor = ActionCommandExecutor(outbox: outbox, tasks: FakeTaskSource(), calendar: calendar, now: { date })

    _ = await executor.executeNext()

    let mutations = await calendar.mutations
    guard case let .createConfirmedMeeting(meeting) = mutations.first else {
        Issue.record("Expected a confirmed meeting mutation")
        return
    }
    #expect(meeting.participants == desired.participants)
    #expect(meeting.location == desired.location)
    #expect(meeting.callLink == desired.callLink)
    #expect(meeting.timezoneIdentifier == desired.timezoneIdentifier)
}

@Test
func calendarReconciliationUpdatesAnOwnedBlockToTheDesiredState() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = CalendarCommitment(
        id: "owned-event",
        title: "Old title",
        start: date,
        end: date.addingTimeInterval(1_800),
        calendarIdentifier: "zoid-calendar",
        ownershipToken: "owned-token"
    )
    let calendar = FakeCalendarSource(commitments: [existing])
    let desired = CalendarBlockDesiredState(
        title: "Deep work",
        start: date.addingTimeInterval(3_600),
        end: date.addingTimeInterval(7_200),
        ownershipToken: "owned-token",
        planItemID: "plan-1"
    )
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .reconcileCalendarBlock,
        entityID: existing.id,
        desiredState: .calendarBlock(desired),
        date: date
    )])

    let result = await ActionCommandExecutor(outbox: outbox, tasks: FakeTaskSource(), calendar: calendar, now: { date }).executeNext()

    #expect(result == .succeeded(commandID: "command-1", platformIdentifier: "owned-event"))
    #expect(await calendar.commitment(identifier: existing.id)?.title == "Deep work")
    #expect(await calendar.mutations == [.updateOwnedBlock(
        identifier: "owned-event",
        CalendarBlockMutation(
            title: desired.title,
            start: desired.start,
            end: desired.end,
            ownershipToken: desired.ownershipToken,
            planItemID: desired.planItemID
        )
    )])
}

@Test
func reminderPriorityCommandUpdatesPriorityAndOwnedMetadataMarker() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let task = SourceTask(
        id: "reminder-1",
        title: "Submit proposal",
        listIdentifier: "work",
        priority: 0,
        dueDate: nil,
        notes: "Keep this note",
        isCompleted: false
    )
    let tasks = FakeTaskSource(tasks: [task])
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .setReminderPriority,
        entityID: task.id,
        desiredState: .reminder(ReminderDesiredState(priority: 9, metadataMarker: "zoid:plan:7")),
        date: date
    )])
    let executor = ActionCommandExecutor(outbox: outbox, tasks: tasks, calendar: FakeCalendarSource(), now: { date })

    let result = await executor.executeNext()

    #expect(result == .succeeded(commandID: "command-1", platformIdentifier: "reminder-1"))
    #expect(await tasks.mutations == [.setPriority(9), .setMetadataMarker("zoid:plan:7")])
    #expect(try await tasks.task(identifier: task.id)?.priority == 9)
    #expect(try await tasks.task(identifier: task.id)?.notes == "Keep this note\nzoid:plan:7")
}

@Test
func reminderPriorityRejectsValuesOutsideEventKitsDefinedScale() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let task = SourceTask(
        id: "reminder-1",
        title: "Submit proposal",
        listIdentifier: "work",
        priority: 0,
        dueDate: nil,
        notes: nil,
        isCompleted: false
    )
    let tasks = FakeTaskSource(tasks: [task])
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .setReminderPriority,
        entityID: task.id,
        desiredState: .reminder(ReminderDesiredState(priority: 7)),
        date: date
    )])

    let result = await ActionCommandExecutor(outbox: outbox, tasks: tasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(result == .terminalFailure(commandID: "command-1", reason: "invalid_desired_state"))
    #expect(await tasks.mutations.isEmpty)
}

@Test
func reminderDueDateCommandCanSetAndClearDueDateDeterministically() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let due = date.addingTimeInterval(86_400)
    let initial = SourceTask(
        id: "reminder-1",
        title: "Invoice",
        listIdentifier: "work",
        priority: 0,
        dueDate: nil,
        notes: nil,
        isCompleted: false
    )
    let tasks = FakeTaskSource(tasks: [initial])
    let setQueue = FakeActionCommandQueue(commands: [makeCommand(
        type: .setReminderDueDate,
        entityID: initial.id,
        desiredState: .reminder(ReminderDesiredState(dueDate: due)),
        date: date
    )])
    _ = await ActionCommandExecutor(outbox: setQueue, tasks: tasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(try await tasks.task(identifier: initial.id)?.dueDate == due)

    let clearQueue = FakeActionCommandQueue(commands: [makeCommand(
        type: .setReminderDueDate,
        entityID: initial.id,
        desiredState: .reminder(ReminderDesiredState(shouldClearDueDate: true)),
        date: date
    )])
    let result = await ActionCommandExecutor(outbox: clearQueue, tasks: tasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(result == .succeeded(commandID: "command-1", platformIdentifier: "reminder-1"))
    #expect(try await tasks.task(identifier: initial.id)?.dueDate == nil)
    #expect(await tasks.mutations == [.setDueDate(due), .setDueDate(nil)])
}

@Test
func reminderMetadataCommandReplacesOnlyZoidOwnedMetadata() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let initial = SourceTask(
        id: "reminder-1",
        title: "Follow up",
        listIdentifier: "work",
        priority: 0,
        dueDate: nil,
        notes: "Human note\nzoid:old-plan",
        isCompleted: false
    )
    let tasks = FakeTaskSource(tasks: [initial])
    let outbox = FakeActionCommandQueue(commands: [makeCommand(
        type: .setReminderMetadata,
        entityID: initial.id,
        desiredState: .reminder(ReminderDesiredState(metadataMarker: "zoid:new-plan")),
        date: date
    )])

    let result = await ActionCommandExecutor(outbox: outbox, tasks: tasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(result == .succeeded(commandID: "command-1", platformIdentifier: "reminder-1"))
    #expect(try await tasks.task(identifier: initial.id)?.notes == "Human note\nzoid:new-plan")
}

@Test
func temporarySourceFailureIsRetriedWhilePermissionFailureIsTerminal() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let command = makeCommand(
        type: .completeReminder,
        entityID: "reminder-1",
        desiredState: .completeReminder,
        date: date
    )
    let retryQueue = FakeActionCommandQueue(commands: [command])
    let retryTasks = FakeTaskSource(readError: .temporarilyUnavailable)
    let retryResult = await ActionCommandExecutor(outbox: retryQueue, tasks: retryTasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(retryResult == .retryableFailure(commandID: "command-1", reason: "source_temporarily_unavailable"))
    #expect(await retryQueue.retryableFailures == ["command-1"])

    let terminalQueue = FakeActionCommandQueue(commands: [command])
    let deniedTasks = FakeTaskSource(readError: .accessDenied)
    let terminalResult = await ActionCommandExecutor(outbox: terminalQueue, tasks: deniedTasks, calendar: FakeCalendarSource(), now: { date }).executeNext()

    #expect(terminalResult == .terminalFailure(commandID: "command-1", reason: "access_denied"))
    #expect(await terminalQueue.terminalFailures == ["command-1"])
}

@Test
func executorConsumesAndFinalizesARealSQLiteOutboxCommand() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-action-executor-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let outbox = try ActionOutboxStore(databaseURL: url, now: { date }, makeID: { UUID().uuidString })
    let task = SourceTask(
        id: "reminder-1",
        title: "Ship release",
        listIdentifier: "work",
        priority: 0,
        dueDate: nil,
        notes: nil,
        isCompleted: false
    )
    let desired = ActionDesiredState.reminder(ReminderDesiredState(priority: 9))
    let enqueued = try outbox.enqueue(type: .setReminderPriority, entityID: task.id, desiredState: desired, planVersion: 1)
    let executor = ActionCommandExecutor(
        outbox: outbox,
        tasks: FakeTaskSource(tasks: [task]),
        calendar: FakeCalendarSource(),
        now: { date }
    )

    let result = await executor.executeNext()

    #expect(result == .succeeded(commandID: enqueued.command.id, platformIdentifier: task.id))
    #expect(try outbox.recentCommands().map(\.state) == [.succeeded])
    #expect(try outbox.attempts(commandID: enqueued.command.id).map(\.state) == [.succeeded])
}

private func makeCommand(
    type: ActionCommandType,
    entityID: String,
    desiredState: ActionDesiredState,
    state: ActionCommandState = .pending,
    attemptCount: Int = 0,
    date: Date
) -> ActionCommand {
    ActionCommand(
        id: "command-1",
        idempotencyKey: "key-1",
        type: type,
        entityID: entityID,
        desiredState: desiredState,
        state: state,
        attemptCount: attemptCount,
        createdAt: date,
        updatedAt: date
    )
}

private actor FakeActionCommandQueue: ActionCommandQueue {
    private var commands: [ActionCommand]
    private var executing: [ActionCommand]
    private(set) var successes: [String] = []
    private(set) var terminalFailures: [String] = []
    private(set) var retryableFailures: [String] = []
    private let failSuccessFinalization: Bool

    init(commands: [ActionCommand] = [], executing: [ActionCommand] = [], failSuccessFinalization: Bool = false) {
        self.commands = commands
        self.executing = executing
        self.failSuccessFinalization = failSuccessFinalization
    }

    func executingCommands() throws -> [ActionCommand] {
        defer { executing.removeAll() }
        return executing
    }

    func claimNextReady() throws -> ActionCommand? {
        guard !commands.isEmpty else { return nil }
        return commands.removeFirst()
    }

    func markSucceeded(_ command: ActionCommand, platformIdentifier: String?) throws {
        if failSuccessFinalization { throw FakeQueueError.write }
        successes.append(command.id)
    }

    func markFailed(_ command: ActionCommand, retryable: Bool, redactedError: String, retryAt: Date?) throws {
        if retryable { retryableFailures.append(command.id) } else { terminalFailures.append(command.id) }
    }
}

private enum FakeQueueError: Error { case write }

private actor FakeCalendarSource: CalendarSource {
    private var commitments: [CalendarCommitment]
    private(set) var mutations: [CalendarSourceMutation] = []

    init(commitments: [CalendarCommitment] = []) { self.commitments = commitments }

    func commitment(identifier: String) -> CalendarCommitment? {
        commitments.first { $0.id == identifier }
    }

    func ownedCommitment(ownershipToken: String) -> CalendarCommitment? {
        commitments.first { $0.ownershipToken == ownershipToken }
    }

    func confirmedMeeting(fingerprint: String) -> CalendarCommitment? {
        commitments.first { $0.meetingFingerprint == fingerprint }
    }

    func apply(_ mutation: CalendarSourceMutation) -> CalendarCommitment? {
        mutations.append(mutation)
        switch mutation {
        case let .createBlock(block):
            let created = CalendarCommitment(
                id: "created-event",
                title: block.title,
                start: block.start,
                end: block.end,
                calendarIdentifier: "zoid-calendar",
                ownershipToken: block.ownershipToken
            )
            commitments.append(created)
            return created
        case let .updateOwnedBlock(identifier, block):
            guard let index = commitments.firstIndex(where: { $0.id == identifier }) else { return nil }
            let updated = CalendarCommitment(
                id: identifier,
                title: block.title,
                start: block.start,
                end: block.end,
                calendarIdentifier: commitments[index].calendarIdentifier,
                ownershipToken: block.ownershipToken
            )
            commitments[index] = updated
            return updated
        case let .deleteOwnedBlock(identifier, _):
            commitments.removeAll { $0.id == identifier }
            return nil
        case let .createConfirmedMeeting(meeting):
            let created = CalendarCommitment(
                id: "created-meeting",
                title: meeting.title,
                start: meeting.start,
                end: meeting.end,
                calendarIdentifier: meeting.calendarIdentifier ?? "default-calendar",
                meetingFingerprint: meeting.fingerprint
            )
            commitments.append(created)
            return created
        }
    }
}

private actor FakeTaskSource: TaskSource {
    private var tasks: [SourceTask]
    private let readError: ActionSourceError?
    private(set) var mutations: [TaskSourceMutation] = []

    init(tasks: [SourceTask] = [], readError: ActionSourceError? = nil) {
        self.tasks = tasks
        self.readError = readError
    }

    func task(identifier: String) throws -> SourceTask? {
        if let readError { throw readError }
        return tasks.first { $0.id == identifier }
    }

    func create(title: String, dueDate: Date?, listIdentifier: String?, metadataMarker: String?) throws -> SourceTask {
        let task = SourceTask(
            id: "created-\(tasks.count + 1)",
            title: title,
            listIdentifier: listIdentifier ?? "default-list",
            priority: 0,
            dueDate: dueDate,
            notes: metadataMarker,
            metadataMarker: metadataMarker,
            isCompleted: false
        )
        tasks.append(task)
        return task
    }

    func apply(_ mutation: TaskSourceMutation, to identifier: String) throws -> SourceTask {
        guard let index = tasks.firstIndex(where: { $0.id == identifier }) else {
            throw ActionSourceError.missingEntity
        }
        mutations.append(mutation)
        let old = tasks[index]
        let updated: SourceTask
        switch mutation {
        case let .setPriority(priority):
            updated = replacing(old, priority: priority)
        case let .setDueDate(dueDate):
            updated = replacing(old, dueDate: .some(dueDate))
        case let .setMetadataMarker(marker):
            let preserved = old.notes?.split(separator: "\n").filter { !$0.hasPrefix("zoid:") }.joined(separator: "\n")
            let notes = [preserved, marker].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            updated = replacing(old, notes: notes.isEmpty ? nil : notes, metadataMarker: marker)
        case .complete:
            updated = replacing(old, isCompleted: true)
        }
        tasks[index] = updated
        return updated
    }

    private func replacing(
        _ task: SourceTask,
        priority: Int? = nil,
        dueDate: Date?? = nil,
        notes: String?? = nil,
        metadataMarker: String?? = nil,
        isCompleted: Bool? = nil
    ) -> SourceTask {
        SourceTask(
            id: task.id,
            title: task.title,
            listIdentifier: task.listIdentifier,
            priority: priority ?? task.priority,
            dueDate: dueDate ?? task.dueDate,
            notes: notes ?? task.notes,
            metadataMarker: metadataMarker ?? task.metadataMarker,
            isCompleted: isCompleted ?? task.isCompleted
        )
    }
}
