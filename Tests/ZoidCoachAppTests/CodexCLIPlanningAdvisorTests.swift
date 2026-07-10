import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func codexCLIAdvisorUsesBoundedExecutionAndRedactsPrivateEvidence() async throws {
    let runner = StubCodexCLICommandRunner(
        response: #"{"advice":[{"id":"task-1","adjustment":37,"reason":"Due soon"},{"id":"task-1","adjustment":99,"reason":"Duplicate"}]}"#
    )
    let advisor = CodexCLIPlanningAdvisor(
        remoteEvidencePolicy: .redactedMetadataOnly,
        executableURL: URL(fileURLWithPath: "/test/codex"),
        runner: runner,
        timeout: 2
    )

    let advice = try await advisor.advise(
        on: [
            PlanningAdviceInput(
                id: "private-reminder-id",
                title: "Secret acquisition plan",
                dueDate: Date(timeIntervalSince1970: 1_800_000_000),
                reminderPriority: 9,
                carryoverDays: 2,
                deferralCount: 1,
                recentAlignedMinutes: 15
            )
        ],
        recentBehavior: [PlanningBehaviorEvidence(application: "Safari - Private research", observationCount: 4)]
    )

    let invocation = try #require(runner.invocation())
    let prompt = String(decoding: invocation.stdin, as: UTF8.self)
    #expect(advice == [PlanningAdvice(id: "private-reminder-id", adjustment: 37, reason: "Due soon")])
    #expect(invocation.executable.path == "/test/codex")
    #expect(invocation.arguments.containsSequence(["--sandbox", "read-only"]))
    #expect(invocation.arguments.contains("--ephemeral"))
    #expect(invocation.arguments.contains("--ignore-user-config"))
    #expect(invocation.arguments.containsSequence(["--disable", "shell_tool"]))
    #expect(invocation.arguments.containsSequence(["--disable", "plugins"]))
    #expect(invocation.arguments.containsSequence(["--disable", "memories"]))
    #expect(prompt.contains("Task 1"))
    #expect(prompt.contains("Application 1"))
    #expect(!prompt.contains("Secret acquisition plan"))
    #expect(!prompt.contains("Safari - Private research"))
    #expect(!prompt.contains("private-reminder-id"))
}

@Test
func codexCLIAdvisorCanSendExplicitPrivateContentWithoutLeakingInternalIDs() async throws {
    let runner = StubCodexCLICommandRunner(response: #"{"advice":[]}"#)
    let advisor = CodexCLIPlanningAdvisor(
        remoteEvidencePolicy: .explicitPrivateContent,
        executableURL: URL(fileURLWithPath: "/test/codex"),
        runner: runner
    )

    _ = try await advisor.advise(
        on: [PlanningAdviceInput(id: "internal-id", title: "Prepare board report", dueDate: nil, reminderPriority: 0, carryoverDays: 0, deferralCount: 0, recentAlignedMinutes: 0)],
        recentBehavior: [PlanningBehaviorEvidence(application: "Keynote", observationCount: 2)]
    )

    let invocation = try #require(runner.invocation())
    let prompt = String(decoding: invocation.stdin, as: UTF8.self)
    #expect(prompt.contains("Prepare board report"))
    #expect(prompt.contains("Keynote"))
    #expect(!prompt.contains("internal-id"))
}

@Test
func codexCLIAdvisorRefusesLocalOnlyEvidenceWithoutLaunchingCodex() async {
    let runner = StubCodexCLICommandRunner(response: #"{"advice":[]}"#)
    let advisor = CodexCLIPlanningAdvisor(
        remoteEvidencePolicy: .localOnly,
        executableURL: URL(fileURLWithPath: "/test/codex"),
        runner: runner
    )

    await #expect(throws: CodexCLIPlanningAdvisorError.remoteEvidenceNotAllowed) {
        try await advisor.advise(
            on: [PlanningAdviceInput(id: "id", title: "Title", dueDate: nil, reminderPriority: 0, carryoverDays: 0, deferralCount: 0, recentAlignedMinutes: 0)],
            recentBehavior: []
        )
    }
    #expect(runner.invocation() == nil)
}

@Test
func codexCLIAdvisorRejectsInvalidStructuredOutput() async {
    let runner = StubCodexCLICommandRunner(
        response: #"{"advice":[{"id":"task-1","adjustment":201,"reason":"Out of range"}]}"#
    )
    let advisor = CodexCLIPlanningAdvisor(
        remoteEvidencePolicy: .redactedMetadataOnly,
        executableURL: URL(fileURLWithPath: "/test/codex"),
        runner: runner
    )

    await #expect(throws: CodexCLIPlanningAdvisorError.invalidOutput) {
        try await advisor.advise(
            on: [PlanningAdviceInput(id: "id", title: "Title", dueDate: nil, reminderPriority: 0, carryoverDays: 0, deferralCount: 0, recentAlignedMinutes: 0)],
            recentBehavior: []
        )
    }
}

@Test
func codexCLIAdvisorSurfacesCommandFailureForRulesFallback() async {
    let runner = StubCodexCLICommandRunner(
        response: #"{"advice":[]}"#,
        result: CodexCLIExecutionResult(exitStatus: 1, standardError: Data("authentication required".utf8))
    )
    let advisor = CodexCLIPlanningAdvisor(
        remoteEvidencePolicy: .redactedMetadataOnly,
        executableURL: URL(fileURLWithPath: "/test/codex"),
        runner: runner
    )

    await #expect(throws: CodexCLIPlanningAdvisorError.executionFailed("authentication required")) {
        try await advisor.advise(
            on: [PlanningAdviceInput(id: "id", title: "Title", dueDate: nil, reminderPriority: 0, carryoverDays: 0, deferralCount: 0, recentAlignedMinutes: 0)],
            recentBehavior: []
        )
    }
}

@Test
func processCodexRunnerPrependsTheExecutableDirectoryForLaunchd() {
    let path = ProcessCodexCLICommandRunner.childPath(
        executable: URL(fileURLWithPath: "/Users/example/.hermes/node/bin/codex"),
        inheritedPath: "/usr/bin:/bin"
    )

    #expect(path == "/Users/example/.hermes/node/bin:/usr/bin:/bin")
}

@Test
func processCodexRunnerEnforcesTimeout() async {
    let runner = ProcessCodexCLICommandRunner()

    await #expect(throws: CodexCLIPlanningAdvisorError.timedOut) {
        try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            stdin: Data(),
            timeout: 0.01
        )
    }
}

private struct RecordedCodexCLIInvocation: Equatable {
    let executable: URL
    let arguments: [String]
    let stdin: Data
}

private final class StubCodexCLICommandRunner: CodexCLICommandRunning, @unchecked Sendable {
    private let response: String
    private let result: CodexCLIExecutionResult
    private let lock = NSLock()
    private var recordedInvocation: RecordedCodexCLIInvocation?

    init(
        response: String,
        result: CodexCLIExecutionResult = CodexCLIExecutionResult(exitStatus: 0, standardError: Data())
    ) {
        self.response = response
        self.result = result
    }

    func run(executable: URL, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CodexCLIExecutionResult {
        let outputFlag = try #require(arguments.firstIndex(of: "--output-last-message"))
        let outputURL = URL(fileURLWithPath: arguments[outputFlag + 1])
        try Data(response.utf8).write(to: outputURL, options: .atomic)
        lock.withLock {
            recordedInvocation = RecordedCodexCLIInvocation(executable: executable, arguments: arguments, stdin: stdin)
        }
        return result
    }

    func invocation() -> RecordedCodexCLIInvocation? {
        lock.withLock { recordedInvocation }
    }
}

private extension Array where Element == String {
    func containsSequence(_ sequence: [String]) -> Bool {
        indices.contains { index in
            let end = index + sequence.count
            return end <= count && Array(self[index..<end]) == sequence
        }
    }
}
