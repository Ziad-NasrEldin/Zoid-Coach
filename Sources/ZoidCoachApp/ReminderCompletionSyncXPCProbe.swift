import Foundation
import ServiceManagement
import ZoidCoachCore
import ZoidCoachInfrastructure

enum ReminderCompletionSyncXPCProbe {
    static let argument = "--qa-reminder-completion-sync-xpc-probe"

    static func run() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: Reminder completion sync probe requires a packaged QA runtime\n", stderr)
            return 2
        }
        let result = ProbeResult()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            result.set(await execute(runtime: runtime))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 60) == .success else {
            fputs("FAIL: Reminder completion sync probe timed out\n", stderr)
            return 124
        }
        return result.value
    }

    private static func execute(runtime: RuntimeEnvironment) async -> Int32 {
        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        do {
            let fixture = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
            try fixture.setPermission(.granted, for: .reminders)
            let sourceTask = try await fixture.create(
                title: "Verify failed Reminder completion recovery",
                dueDate: Date(),
                listIdentifier: "qa-inbox",
                metadataMarker: "qa:completion-sync"
            )
            try restart(service)
            defer { try? service.unregister() }

            let client = TodayDashboardXPCClient(runtimeEnvironment: runtime)
            let day = Date()
            _ = try await applyAfterStartup(client, .synchronizeReminderSnapshots([
                AgentReminderSnapshot(
                    id: sourceTask.id,
                    title: sourceTask.title,
                    dueDate: sourceTask.dueDate,
                    priority: sourceTask.priority,
                    notes: sourceTask.notes,
                    listID: sourceTask.listIdentifier,
                    listName: "QA Inbox",
                    modificationDate: day
                )
            ]))
            _ = try await client.apply(.replaceDailyPlan(items: [
                AgentPlanItem(
                    reminderID: sourceTask.id,
                    rank: 1,
                    isMainObjective: true,
                    estimateMinutes: 15,
                    selectionReason: "Signed failure recovery",
                    selectionScore: 100
                )
            ], day: day))
            _ = try await client.apply(.start, taskID: sourceTask.id)

            try fixture.setPermission(.denied, for: .reminders)
            let completed = try await client.apply(.complete, taskID: sourceTask.id)
            guard !completed.taskRows.contains(where: { $0.taskID == sourceTask.id }) else {
                return fail(4, "locally completed task remained in the active Today list")
            }
            let failed = try await waitForPhase(.failed, taskID: sourceTask.id, client: client)
            guard failed.canRetry, failed.attemptCount == 1 else {
                return fail(5, "denied source write did not become an explicit retryable UI state")
            }

            try fixture.setPermission(.granted, for: .reminders)
            let queued = try await client.retryReminderCompletion(taskID: sourceTask.id)
            guard queued.phase == .pending else {
                return fail(6, "explicit retry did not requeue the exact failed command")
            }
            let confirmed = try await waitForPhase(.confirmed, taskID: sourceTask.id, client: client)
            guard confirmed.attemptCount == 2,
                  try await fixture.task(identifier: sourceTask.id)?.isCompleted == true else {
                return fail(7, "retry did not reach source-confirmed completion on its second attempt")
            }

            try restart(service)
            let restored = try await waitForPhase(.confirmed, taskID: sourceTask.id, client: client)
            let history = try TaskHistoryStore(databaseURL: runtime.databaseURL).completedEntries(for: day)
            guard restored.commandID == confirmed.commandID,
                  history.filter({ $0.taskID == sourceTask.id }).count == 1 else {
                return fail(8, "confirmed sync identity or local completion history did not survive restart")
            }

            print("PASS: signed QA Reminder denial, local completion, task-specific failure, repair, exact retry, source confirmation, history preservation, and restart")
            return 0
        } catch {
            return fail(9, "Reminder completion sync probe failed: \(error.localizedDescription)")
        }
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
        throw lastError ?? ProbeError.agentUnavailable
    }

    private static func waitForPhase(
        _ expected: ReminderCompletionSyncPhase,
        taskID: String,
        client: TodayDashboardXPCClient
    ) async throws -> ReminderCompletionSyncState {
        var last = try await client.fetchReminderCompletionSync(taskID: taskID)
        for _ in 0..<30 {
            if last.phase == expected { return last }
            try await Task.sleep(for: .milliseconds(500))
            last = try await client.fetchReminderCompletionSync(taskID: taskID)
        }
        throw ProbeError.unexpectedPhase(expected: expected, actual: last.phase)
    }

    private static func restart(_ service: SMAppService) throws {
        if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }
        try service.register()
        guard service.status != .requiresApproval else { throw ProbeError.requiresApproval }
    }

    private static func fail(_ code: Int32, _ message: String) -> Int32 {
        fputs("FAIL: \(message)\n", stderr)
        return code
    }
}

private enum ProbeError: LocalizedError {
    case agentUnavailable
    case requiresApproval
    case unexpectedPhase(expected: ReminderCompletionSyncPhase, actual: ReminderCompletionSyncPhase)

    var errorDescription: String? {
        switch self {
        case .agentUnavailable: "The QA agent did not become reachable."
        case .requiresApproval: "The QA LaunchAgent requires manual approval."
        case let .unexpectedPhase(expected, actual): "Expected \(expected.rawValue), got \(actual.rawValue)."
        }
    }
}

private final class ProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 1

    var value: Int32 { lock.withLock { stored } }
    func set(_ value: Int32) { lock.withLock { stored = value } }
}
