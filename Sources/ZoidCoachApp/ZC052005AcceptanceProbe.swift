import Foundation
import ServiceManagement
import SQLite3
import ZoidCoachCore
import ZoidCoachInfrastructure

enum ZC052005AcceptanceProbe {
    static let argument = "--qa-zc052005-acceptance"

    enum Mode: String, Equatable {
        case prepareExternalReminder = "prepare-external-reminder"
        case temporaryLock = "temporary-lock"
        case lostTaskReply = "lost-task-reply"
        case calendarLostReply = "calendar-lost-reply"
        case holdLock = "hold-lock"

        init?(argument: String) {
            self.init(rawValue: argument)
        }
    }

    static func isAvailable(in runtime: RuntimeEnvironment) -> Bool {
        guard case .qa = runtime.mode else { return false }
        return runtime.packageMode == .qa && runtime.identity == .qa
    }

    static func run(arguments: [String] = CommandLine.arguments) -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard isAvailable(in: runtime) else {
            return fail(2, "ZC-052-005 acceptance controls require a signed packaged QA runtime.")
        }
        guard let markerIndex = arguments.firstIndex(of: argument),
              arguments.indices.contains(markerIndex + 1),
              let mode = Mode(argument: arguments[markerIndex + 1]) else {
            return fail(3, "Choose a named ZC-052-005 acceptance mode.")
        }
        if mode == .holdLock {
            let milliseconds = arguments.indices.contains(markerIndex + 2)
                ? Int(arguments[markerIndex + 2]) ?? 5_000
                : 5_000
            return holdLock(runtime: runtime, milliseconds: min(max(milliseconds, 100), 15_000))
        }

        let result = ZC052005ProbeResult()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            result.set(await execute(mode: mode, runtime: runtime))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 60) == .success else {
            return fail(124, "ZC-052-005 acceptance mode timed out.")
        }
        return result.value
    }

    private static func execute(mode: Mode, runtime: RuntimeEnvironment) async -> Int32 {
        do {
            switch mode {
            case .prepareExternalReminder:
                let prepared = try await prepareExternalReminder(runtime: runtime, start: true)
                print("PASS: external Reminder task prepared for signed UI acceptance: \(prepared.taskID)")
            case .temporaryLock:
                try await verifyTemporaryLock(runtime: runtime)
                print("PASS: temporary real database lock produced one external completion operation, outbox command, and history row")
            case .lostTaskReply:
                try await verifyLostTaskReply(runtime: runtime)
                print("PASS: lost task reply reused one pending operation across helper relaunch without duplicate effects")
            case .calendarLostReply:
                try await verifyCalendarLostReply(runtime: runtime)
                print("PASS: Calendar lost reply reconciled the same complete command set across helper relaunch")
            case .holdLock:
                return fail(4, "The hold-lock mode must run synchronously.")
            }
            return 0
        } catch {
            return fail(5, error.localizedDescription)
        }
    }

    private static func verifyTemporaryLock(runtime: RuntimeEnvironment) async throws {
        let prepared = try await prepareExternalReminder(runtime: runtime, start: true)
        try prepared.fixture.setPermission(.denied, for: .reminders)
        let blocker = try SQLiteExclusiveLock(databaseURL: runtime.databaseURL)
        let client = prepared.client
        let taskID = prepared.taskID
        async let completion = client.apply(.complete, taskID: taskID)
        try await Task.sleep(for: .milliseconds(80))
        blocker.release()
        _ = try await completion
        try restart(prepared.service)
        _ = try await fetchAfterStartup(prepared.client)
        try requireRawCardinalities(databaseURL: runtime.databaseURL, taskID: prepared.taskID)
    }

    private static func verifyLostTaskReply(runtime: RuntimeEnvironment) async throws {
        let prepared = try await prepareExternalReminder(runtime: runtime, start: true)
        try prepared.fixture.setPermission(.denied, for: .reminders)
        let state = TaskMutationClientState(
            defaults: runtime.makeUserDefaults(),
            namespace: runtime.identity.machServiceName
        )
        let request = state.request(command: .complete, taskID: prepared.taskID)
        _ = try await prepared.client.apply(request)
        guard state.pendingTaskRequests() == [request] else {
            throw ZC052005ProbeError.pendingIdentityLost
        }
        try restart(prepared.service)
        let relaunched = TodayDashboardXPCClient(runtimeEnvironment: runtime)
        let snapshots = await relaunched.reconcilePendingTaskMutations()
        guard snapshots.count == 1, state.pendingTaskRequests().isEmpty else {
            throw ZC052005ProbeError.pendingIdentityLost
        }
        try requireRawCardinalities(databaseURL: runtime.databaseURL, taskID: prepared.taskID)
    }

    private static func verifyCalendarLostReply(runtime: RuntimeEnvironment) async throws {
        let prepared = try await prepareExternalReminder(runtime: runtime, start: false)
        let state = TaskMutationClientState(
            defaults: runtime.makeUserDefaults(),
            namespace: runtime.identity.machServiceName
        )
        let request = state.calendarPlanRequest(day: Date())
        let committed = try await prepared.client.apply(
            .schedulePlan(day: request.day, operationID: request.operationID)
        )
        guard committed.accepted, !committed.commandIDs.isEmpty,
              state.pendingCalendarPlanRequests() == [request] else {
            throw ZC052005ProbeError.incompleteCalendarReceipt
        }
        try restart(prepared.service)
        let relaunched = TodayDashboardXPCClient(runtimeEnvironment: runtime)
        let receipts = await relaunched.reconcilePendingCalendarPlans()
        guard receipts.count == 1,
              Set(receipts[0].commandIDs) == Set(committed.commandIDs),
              state.pendingCalendarPlanRequests().isEmpty else {
            throw ZC052005ProbeError.incompleteCalendarReceipt
        }
        let outbox = try ActionOutboxStore(databaseURL: runtime.databaseURL)
        let committedCommands = try committed.commandIDs.compactMap(outbox.command(commandID:))
        guard committedCommands.count == Set(committed.commandIDs).count else {
            throw ZC052005ProbeError.incompleteCalendarReceipt
        }
    }

    private static func prepareExternalReminder(
        runtime: RuntimeEnvironment,
        start: Bool
    ) async throws -> PreparedReminder {
        let fixture = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
        try fixture.setPermission(.granted, for: .reminders)
        try fixture.setPermission(.granted, for: .calendar)
        let source = try await fixture.create(
            title: "ZC-052-005 external Reminder acceptance",
            dueDate: nil,
            listIdentifier: "qa-inbox",
            metadataMarker: "qa:zc052005"
        )
        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        try restart(service)
        let client = TodayDashboardXPCClient(runtimeEnvironment: runtime)
        let day = Date()
        _ = try await applyAfterStartup(client, .synchronizeReminderSnapshots([
            AgentReminderSnapshot(
                id: source.id,
                title: source.title,
                dueDate: source.dueDate,
                priority: source.priority,
                notes: source.notes,
                listID: source.listIdentifier,
                listName: "QA Inbox",
                modificationDate: day
            )
        ]))
        _ = try await client.apply(.replaceDailyPlan(items: [
            AgentPlanItem(
                reminderID: source.id,
                rank: 1,
                isMainObjective: true,
                estimateMinutes: 15,
                selectionReason: "ZC-052-005 signed acceptance",
                selectionScore: 100
            )
        ], day: day))
        if start { _ = try await client.apply(.start, taskID: source.id) }
        return PreparedReminder(taskID: source.id, fixture: fixture, client: client, service: service)
    }

    private static func applyAfterStartup(
        _ client: TodayDashboardXPCClient,
        _ command: AgentMutationCommand
    ) async throws -> AgentMutationReceipt {
        var lastError: Error?
        for _ in 0..<16 {
            do { return try await client.apply(command) }
            catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? ZC052005ProbeError.agentUnavailable
    }

    private static func fetchAfterStartup(_ client: TodayDashboardXPCClient) async throws -> TodaySnapshot {
        var lastError: Error?
        for _ in 0..<16 {
            do { return try await client.fetchTodaySnapshot() }
            catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? ZC052005ProbeError.agentUnavailable
    }

    private static func restart(_ service: SMAppService) throws {
        if service.status != .notRegistered && service.status != .notFound { try service.unregister() }
        try service.register()
        guard service.status != .requiresApproval else { throw ZC052005ProbeError.requiresApproval }
    }

    private static func holdLock(runtime: RuntimeEnvironment, milliseconds: Int) -> Int32 {
        do {
            let lock = try SQLiteExclusiveLock(databaseURL: runtime.databaseURL)
            print("LOCK READY: \(milliseconds)ms")
            fflush(stdout)
            Thread.sleep(forTimeInterval: TimeInterval(milliseconds) / 1_000)
            lock.release()
            print("LOCK RELEASED")
            return 0
        } catch {
            return fail(6, error.localizedDescription)
        }
    }

    private static func requireRawCardinalities(databaseURL: URL, taskID: String) throws {
        guard try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_mutation_operations WHERE task_id = ? AND command = 'complete';", taskID) == 1,
              try scalarCount(databaseURL, "SELECT COUNT(*) FROM action_commands WHERE entity_id = ? AND action_type = 'completeReminder';", taskID) == 1,
              try scalarCount(databaseURL, "SELECT COUNT(*) FROM task_history WHERE task_id = ? AND state = 'completed';", taskID) == 1 else {
            throw ZC052005ProbeError.duplicateOrMissingEffects
        }
    }

    private static func scalarCount(_ url: URL, _ sql: String, _ value: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else { throw ZC052005ProbeError.databaseUnavailable }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw ZC052005ProbeError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, value, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ZC052005ProbeError.databaseUnavailable }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func fail(_ code: Int32, _ message: String) -> Int32 {
        fputs("FAIL: \(message)\n", stderr)
        return code
    }
}

private struct PreparedReminder {
    let taskID: String
    let fixture: DeterministicOSFixtureAdapters
    let client: TodayDashboardXPCClient
    let service: SMAppService
}

private final class SQLiteExclusiveLock: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()

    init(databaseURL: URL) throws {
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database,
              sqlite3_exec(database, "BEGIN EXCLUSIVE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw ZC052005ProbeError.databaseUnavailable
        }
    }

    func release() {
        lock.withLock {
            guard let database else { return }
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            sqlite3_close(database)
            self.database = nil
        }
    }

    deinit { release() }
}

private enum ZC052005ProbeError: LocalizedError {
    case agentUnavailable
    case requiresApproval
    case databaseUnavailable
    case pendingIdentityLost
    case incompleteCalendarReceipt
    case duplicateOrMissingEffects

    var errorDescription: String? {
        switch self {
        case .agentUnavailable: "The signed QA agent did not become reachable."
        case .requiresApproval: "The signed QA agent requires manual approval."
        case .databaseUnavailable: "The isolated QA database could not be locked or inspected."
        case .pendingIdentityLost: "The pending task operation identity was not retained across relaunch."
        case .incompleteCalendarReceipt: "The complete Calendar command receipt was not reconciled across relaunch."
        case .duplicateOrMissingEffects: "The task mutation did not retain exactly one operation, outbox command, and history row."
        }
    }
}

private final class ZC052005ProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 1
    var value: Int32 { lock.withLock { stored } }
    func set(_ value: Int32) { lock.withLock { stored = value } }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
