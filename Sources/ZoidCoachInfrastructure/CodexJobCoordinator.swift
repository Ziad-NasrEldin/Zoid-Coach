import Darwin
import Foundation
import ZoidCoachCore

public protocol CodexJobLaunching: Sendable {
    func run(job: CodexJob) async throws -> String
}

public actor CodexJobCoordinator {
    private let persistence: VoicePersistenceStore
    private let launcher: any CodexJobLaunching
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(
        persistence: VoicePersistenceStore,
        launcher: any CodexJobLaunching = ProcessCodexJobLauncher(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.persistence = persistence
        self.launcher = launcher
        self.now = now
        self.makeID = makeID
    }

    public func start(workspacePath: String, objective: String, sandbox: CodexJobSandbox) throws -> CodexJob {
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = URL(fileURLWithPath: workspacePath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard !trimmedObjective.isEmpty,
              FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CodexJobCoordinatorError.invalidRequest
        }
        let createdAt = now()
        let queued = CodexJob(
            id: makeID(),
            workspacePath: workspace.path,
            objective: trimmedObjective,
            sandbox: sandbox,
            state: .queued,
            createdAt: createdAt
        )
        try persistence.save(queued)
        let task = Task { [weak self, launcher, queued] in
            guard let self else { return }
            await self.run(queued, launcher: launcher)
        }
        tasks[queued.id] = task
        return queued
    }

    public func job(id: String) throws -> CodexJob? { try persistence.codexJob(id: id) }

    public func activeJobs() throws -> [CodexJob] {
        try persistence.codexJobs(states: [.queued, .running])
    }

    public func cancel(jobID: String) throws -> CodexJob {
        guard let existing = try persistence.codexJob(id: jobID),
              existing.state == .queued || existing.state == .running else {
            throw CodexJobCoordinatorError.notCancellable
        }
        tasks[jobID]?.cancel()
        tasks[jobID] = nil
        let cancelled = updated(
            existing,
            state: .cancelled,
            finishedAt: now(),
            resultSummary: nil,
            redactedError: nil
        )
        try persistence.save(cancelled)
        return cancelled
    }

    public func recoverInterruptedJobs() throws {
        for job in try persistence.codexJobs(states: [.queued, .running]) {
            let failed = updated(
                job,
                state: .failed,
                finishedAt: now(),
                resultSummary: nil,
                redactedError: "Zoid restarted before this job completed."
            )
            try persistence.save(failed)
        }
    }

    private func run(_ queued: CodexJob, launcher: any CodexJobLaunching) async {
        let running = updated(
            queued,
            state: .running,
            startedAt: now(),
            finishedAt: nil,
            resultSummary: nil,
            redactedError: nil
        )
        do {
            try persistence.save(running)
            let summary = try await launcher.run(job: running)
            guard !Task.isCancelled else { throw CancellationError() }
            try persistence.save(updated(
                running,
                state: .succeeded,
                finishedAt: now(),
                resultSummary: summary,
                redactedError: nil
            ))
        } catch is CancellationError {
            if (try? persistence.codexJob(id: queued.id)?.state) != .cancelled {
                try? persistence.save(updated(
                    running,
                    state: .cancelled,
                    finishedAt: now(),
                    resultSummary: nil,
                    redactedError: nil
                ))
            }
        } catch {
            try? persistence.save(updated(
                running,
                state: .failed,
                finishedAt: now(),
                resultSummary: nil,
                redactedError: String(error.localizedDescription.prefix(500))
            ))
        }
        tasks[queued.id] = nil
    }

    private func updated(
        _ job: CodexJob,
        state: CodexJobState,
        startedAt: Date? = nil,
        finishedAt: Date?,
        resultSummary: String?,
        redactedError: String?
    ) -> CodexJob {
        CodexJob(
            id: job.id,
            workspacePath: job.workspacePath,
            objective: job.objective,
            sandbox: job.sandbox,
            state: state,
            createdAt: job.createdAt,
            startedAt: startedAt ?? job.startedAt,
            finishedAt: finishedAt,
            resultSummary: resultSummary,
            redactedError: redactedError
        )
    }
}

public final class ProcessCodexJobLauncher: CodexJobLaunching, @unchecked Sendable {
    private let executableURL: URL?
    private let timeout: TimeInterval

    public init(executableURL: URL? = nil, timeout: TimeInterval = 1_800) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    public func run(job: CodexJob) async throws -> String {
        guard let executable = executableURL ?? Self.resolveExecutable() else {
            throw CodexJobCoordinatorError.executableUnavailable
        }
        let context = try CodexProcessContext(executable: executable, job: job)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                context.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            context.cancel()
        }
    }

    private static func resolveExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let configured = environment["ZOID_CODEX_CLI_PATH"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured))
        }
        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") })
        candidates.append(contentsOf: [
            home.appendingPathComponent(".hermes/node/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class CodexProcessContext: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let standardInput = Pipe()
    private let directory: URL
    private let outputURL: URL
    private let errorURL: URL
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let prompt: Data
    private var isFinished = false
    private var isCancelled = false

    init(executable: URL, job: CodexJob) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-codex-job-\(job.id)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        outputURL = directory.appendingPathComponent("stdout.log")
        errorURL = directory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        outputHandle = try FileHandle(forWritingTo: outputURL)
        errorHandle = try FileHandle(forWritingTo: errorURL)
        var codexArguments = [
            "exec",
            "--sandbox", job.sandbox == .workspaceWrite ? "workspace-write" : "read-only",
            "--ephemeral",
            "--skip-git-repo-check",
            "--cd", job.workspacePath,
            "--color", "never",
            "-"
        ]
        if job.sandbox == .workspaceWrite,
           FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            let gitMetadata = URL(fileURLWithPath: job.workspacePath)
                .resolvingSymlinksInPath()
                .appendingPathComponent(".git").path
            let escapedPath = gitMetadata.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let profile = "(version 1) (allow default) (deny file-write* (subpath \"\(escapedPath)\"))"
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile, executable.path] + codexArguments
        } else {
            process.executableURL = executable
            process.arguments = codexArguments
        }
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = standardInput
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        prompt = Data("""
        Complete this scoped Zoid Coach job inside the supplied workspace:

        \(job.objective)

        Do not commit, push, deploy, publish, send messages, purchase anything, expose credentials, or modify files outside the workspace.
        Report the verified outcome and any remaining blocker concisely.
        """.utf8)
    }

    deinit { cleanup() }

    func start(timeout: TimeInterval, continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            finish(continuation: continuation, result: .failure(CancellationError()))
            return
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let result: Result<String, Error>
            if self.timedOut {
                result = .failure(CodexJobCoordinatorError.timedOut)
            } else if self.cancelled {
                result = .failure(CancellationError())
            } else if process.terminationStatus == 0 {
                result = .success(self.readSummary())
            } else {
                result = .failure(CodexJobCoordinatorError.executionFailed(self.readError()))
            }
            self.finish(continuation: continuation, result: result)
        }
        do {
            try process.run()
            try standardInput.fileHandleForWriting.write(contentsOf: prompt)
            try standardInput.fileHandleForWriting.close()
        } catch {
            finish(continuation: continuation, result: .failure(error))
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.timeOut(continuation: continuation)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let running = process.isRunning
        lock.unlock()
        if running { process.terminate() }
    }

    private var cancelled: Bool { lock.withLock { isCancelled } }
    private var didTimeOut = false
    private var timedOut: Bool { lock.withLock { didTimeOut } }

    private func timeOut(continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        didTimeOut = true
        let running = process.isRunning
        lock.unlock()
        if running {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.process.isRunning else { return }
                kill(self.process.processIdentifier, SIGKILL)
            }
        } else {
            finish(continuation: continuation, result: .failure(CodexJobCoordinatorError.timedOut))
        }
    }

    private func finish(continuation: CheckedContinuation<String, Error>, result: Result<String, Error>) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        lock.unlock()
        cleanup()
        continuation.resume(with: result)
    }

    private func readSummary() -> String {
        try? outputHandle.synchronize()
        let output = (try? Data(contentsOf: outputURL)) ?? Data()
        let text = String(decoding: output.suffix(8_000), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Codex completed the job without a textual summary." : text
    }

    private func readError() -> String {
        try? errorHandle.synchronize()
        let data = (try? Data(contentsOf: errorURL)) ?? Data()
        let text = String(decoding: data.suffix(1_000), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Codex exited without a diagnostic." : text
    }

    private func cleanup() {
        try? standardInput.fileHandleForWriting.close()
        try? outputHandle.close()
        try? errorHandle.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

public enum CodexJobCoordinatorError: LocalizedError {
    case invalidRequest
    case executableUnavailable
    case notCancellable
    case timedOut
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: "Choose an existing workspace and provide a non-empty Codex objective."
        case .executableUnavailable: "Codex CLI is not installed or configured for Zoid Coach."
        case .notCancellable: "This Codex job is not queued or running."
        case .timedOut: "The Codex job exceeded its allowed runtime."
        case let .executionFailed(message): "The Codex job failed: \(message)"
        }
    }
}
