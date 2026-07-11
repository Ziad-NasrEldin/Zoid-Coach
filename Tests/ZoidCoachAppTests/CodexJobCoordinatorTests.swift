import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func codexJobTransitionsFromQueuedThroughRunningToSucceeded() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-codex-job-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseURL.path + suffix) }
    }
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let store = try VoicePersistenceStore(databaseURL: databaseURL)
    let launcher = ControlledCodexLauncher()
    let coordinator = CodexJobCoordinator(persistence: store, launcher: launcher)

    let queued = try await coordinator.start(
        workspacePath: FileManager.default.temporaryDirectory.path,
        objective: "Inspect the failing test",
        sandbox: .readOnly
    )
    await launcher.finish(with: "The test failure is isolated.")
    let finished = try await waitForCodexJob(coordinator, id: queued.id, state: .succeeded)

    #expect(queued.state == .queued)
    #expect(finished.resultSummary == "The test failure is isolated.")
    #expect(try store.codexJob(id: queued.id)?.state == .succeeded)
}

@Test
func cancellingCodexJobPersistsCancelledState() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-codex-cancel-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseURL.path + suffix) }
    }
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let coordinator = CodexJobCoordinator(
        persistence: try VoicePersistenceStore(databaseURL: databaseURL),
        launcher: ControlledCodexLauncher()
    )
    let queued = try await coordinator.start(
        workspacePath: FileManager.default.temporaryDirectory.path,
        objective: "Wait for cancellation",
        sandbox: .readOnly
    )

    let cancelled = try await coordinator.cancel(jobID: queued.id)

    #expect(cancelled.state == .cancelled)
}

private actor ControlledCodexLauncher: CodexJobLaunching {
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?

    func run(job: CodexJob) async throws -> String {
        if let pendingResult {
            self.pendingResult = nil
            return try pendingResult.get()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancelContinuation() }
        }
    }

    func finish(with result: String) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: result)
        } else {
            pendingResult = .success(result)
        }
    }

    private func cancelContinuation() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }
}

private func waitForCodexJob(
    _ coordinator: CodexJobCoordinator,
    id: String,
    state: CodexJobState
) async throws -> CodexJob {
    for _ in 0..<100 {
        if let job = try await coordinator.job(id: id), job.state == state { return job }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw CodexJobTestError.timedOut
}

private enum CodexJobTestError: Error { case timedOut }
