import Foundation
import ServiceManagement
import ZoidCoachCore
import ZoidCoachInfrastructure

enum ManualLocalTaskXPCProbe {
    static let argument = "--qa-manual-local-task-xpc-probe"

    static func run() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: manual local task XPC probe requires a packaged QA runtime\n", stderr)
            return 2
        }

        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        do {
            try restart(service)
        } catch {
            fputs("FAIL: QA LaunchAgent registration failed: \(error.localizedDescription)\n", stderr)
            return 3
        }

        let completion = ManualLocalTaskProbeCompletion()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            completion.set(await execute(runtime: runtime))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 45) == .success else {
            fputs("FAIL: manual local task XPC probe timed out\n", stderr)
            return 124
        }
        try? service.unregister()
        return completion.value
    }

    private static func execute(runtime: RuntimeEnvironment) async -> Int32 {
        let client = TodayDashboardXPCClient(runtimeEnvironment: runtime)
        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        let taskID = "local:user:qa-signed-restart"
        let day = Date()
        let command = AgentMutationCommand.createLocalTask(
            task: AgentLocalTask(
                id: taskID,
                title: "Verify the signed local task journey",
                notes: "Created through the packaged QA XPC boundary",
                estimateMinutes: 25
            ),
            addToToday: true,
            day: day
        )

        do {
            let first = try await applyAfterAgentStartup(client: client, command: command)
            guard first.accepted else {
                fputs("FAIL: the signed agent rejected local task creation\n", stderr)
                return 4
            }
            let replay = try await client.apply(command)
            guard replay.accepted else {
                fputs("FAIL: exact local task replay was rejected\n", stderr)
                return 5
            }

            var snapshot = try await fetchAfterRestart(client: client, service: service)
            guard snapshot.taskRows.contains(where: { $0.taskID == taskID }) else {
                fputs("FAIL: local task did not survive the first agent restart in Today\n", stderr)
                return 6
            }

            snapshot = try await client.apply(.start, taskID: taskID)
            guard snapshot.activeTask?.taskID == taskID else {
                fputs("FAIL: local task did not enter the active state\n", stderr)
                return 7
            }
            snapshot = try await client.apply(.complete, taskID: taskID)
            guard snapshot.activeTask?.taskID != taskID,
                  !snapshot.taskRows.contains(where: { $0.taskID == taskID }) else {
                fputs("FAIL: completed local task remained active in Today\n", stderr)
                return 8
            }

            snapshot = try await fetchAfterRestart(client: client, service: service)
            guard !snapshot.taskRows.contains(where: { $0.taskID == taskID }),
                  snapshot.unplannedReminders?.contains(where: { $0.reminderID == taskID }) != true else {
                fputs("FAIL: completed local task returned after the second agent restart\n", stderr)
                return 9
            }

            let reminders = try ReminderSnapshotStore(databaseURL: runtime.databaseURL)
            let history = try TaskHistoryStore(databaseURL: runtime.databaseURL)
            let outbox = try ActionOutboxStore(databaseURL: runtime.databaseURL)
            let localTaskIsIncomplete = try reminders.loadIncomplete().contains(where: { $0.id == taskID })
            let completedCount = try history.summary(for: day).completedCount
            let remindersMutationWasQueued = try outbox.recentCommands().contains(where: { $0.entityID == taskID })
            guard !localTaskIsIncomplete,
                  completedCount == 1,
                  !remindersMutationWasQueued else {
                fputs("FAIL: durable completion, history, or Reminders outbox isolation was incorrect\n", stderr)
                return 10
            }

            print("PASS: signed QA local task create, idempotent replay, restart, start, complete, second restart, history, and zero Reminders mutation")
            return 0
        } catch {
            fputs("FAIL: manual local task XPC probe failed: \(error.localizedDescription)\n", stderr)
            return 11
        }
    }

    private static func applyAfterAgentStartup(
        client: TodayDashboardXPCClient,
        command: AgentMutationCommand
    ) async throws -> AgentMutationReceipt {
        var lastError: Error?
        for _ in 0 ..< 12 {
            do { return try await client.apply(command) }
            catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? ManualLocalTaskProbeError.agentUnavailable
    }

    private static func fetchAfterRestart(
        client: TodayDashboardXPCClient,
        service: SMAppService
    ) async throws -> TodaySnapshot {
        try restart(service)
        var lastError: Error?
        for _ in 0 ..< 12 {
            do { return try await client.fetchTodaySnapshot() }
            catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? ManualLocalTaskProbeError.agentUnavailable
    }

    private static func restart(_ service: SMAppService) throws {
        if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }
        try service.register()
        guard service.status != .requiresApproval else {
            throw ManualLocalTaskProbeError.requiresApproval
        }
    }
}

private enum ManualLocalTaskProbeError: Error {
    case agentUnavailable
    case requiresApproval
}

private final class ManualLocalTaskProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 1

    var value: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Int32) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}
