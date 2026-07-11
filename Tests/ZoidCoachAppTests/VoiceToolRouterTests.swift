import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func declaredReversibleVoiceToolExecutesOnlyWithExplicitIntent() async throws {
    let executor = RecordingVoiceToolExecutor()
    let router = VoiceToolRouter(executor: executor)
    let explicit = VoiceToolInvocation(
        id: "invocation-1",
        sessionID: "session-1",
        toolName: "open_application",
        argumentsJSON: #"{"name":"Xcode"}"#,
        originTurnID: "turn-1",
        hasExplicitUserIntent: true,
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let inferred = VoiceToolInvocation(
        id: "invocation-2",
        sessionID: "session-1",
        toolName: "open_application",
        argumentsJSON: #"{"name":"Calendar"}"#,
        originTurnID: nil,
        hasExplicitUserIntent: false,
        requestedAt: explicit.requestedAt
    )

    let executed = await router.handle(explicit)
    let denied = await router.handle(inferred)

    #expect(executed.status == .executed)
    #expect(executed.resultJSON == #"{"ok":true}"#)
    #expect(denied.status == .denied)
    #expect(await executor.calls == ["open_application"])
}

@Test
func conversationalQuestionDoesNotAuthorizeAMacMutation() async throws {
    let executor = RecordingVoiceToolExecutor()
    let router = VoiceToolRouter(executor: executor)
    let question = VoiceToolInvocation(
        id: "invocation-question",
        sessionID: "session-1",
        toolName: "open_application",
        argumentsJSON: #"{"name":"Safari"}"#,
        originTurnID: "turn-1",
        originUserText: "Can you open Safari?",
        hasExplicitUserIntent: true,
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let command = VoiceToolInvocation(
        id: "invocation-command",
        sessionID: "session-1",
        toolName: "open_application",
        argumentsJSON: #"{"name":"Safari"}"#,
        originTurnID: "turn-2",
        originUserText: "Open Safari",
        hasExplicitUserIntent: true,
        requestedAt: question.requestedAt
    )

    #expect(await router.handle(question).status == .denied)
    #expect(await router.handle(command).status == .executed)
    #expect(await executor.calls == ["open_application"])
}

@Test
func externalVoiceToolCreatesApprovalWithoutExecuting() async throws {
    let executor = RecordingVoiceToolExecutor()
    let router = VoiceToolRouter(executor: executor)
    let invocation = VoiceToolInvocation(
        id: "invocation-1",
        sessionID: "session-1",
        toolName: "create_calendar_commitment",
        argumentsJSON: #"{"title":"Client call"}"#,
        originTurnID: "turn-1",
        hasExplicitUserIntent: true,
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let result = await router.handle(invocation)

    #expect(result.status == .approvalRequired)
    #expect(result.approval?.invocationID == invocation.id)
    #expect(await executor.calls.isEmpty)
}

@Test
func approvedExternalVoiceToolExecutesExactlyOnceAfterConfirmation() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-voice-approval-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseURL.path + suffix) }
    }
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let executor = RecordingVoiceToolExecutor()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let router = VoiceToolRouter(
        executor: executor,
        persistence: try VoicePersistenceStore(databaseURL: databaseURL),
        now: { now },
        makeID: { "approval-1" }
    )
    let invocation = VoiceToolInvocation(
        id: "invocation-1",
        sessionID: "session-1",
        toolName: "create_calendar_commitment",
        argumentsJSON: #"{"title":"Client call"}"#,
        originTurnID: "turn-1",
        hasExplicitUserIntent: true,
        requestedAt: now
    )
    let pending = await router.handle(invocation)

    let executed = await router.resolveApproval(id: "approval-1", approved: true)
    let replay = await router.resolveApproval(id: "approval-1", approved: true)

    #expect(pending.status == .approvalRequired)
    #expect(executed.status == .executed)
    #expect(replay.status == .denied)
    #expect(await executor.calls == ["create_calendar_commitment"])
}

@Test
func undeclaredAndArbitraryShellToolsAreDenied() async throws {
    let executor = RecordingVoiceToolExecutor()
    let router = VoiceToolRouter(executor: executor)
    let invocation = VoiceToolInvocation(
        id: "invocation-1",
        sessionID: "session-1",
        toolName: "run_shell",
        argumentsJSON: #"{"command":"rm -rf ~"}"#,
        originTurnID: "turn-1",
        hasExplicitUserIntent: true,
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let result = await router.handle(invocation)

    #expect(result.status == .denied)
    #expect(await executor.calls.isEmpty)
}

private actor RecordingVoiceToolExecutor: VoiceToolActionExecuting {
    var calls: [String] = []

    func execute(toolName: String, argumentsJSON: String) async throws -> String {
        calls.append(toolName)
        return #"{"ok":true}"#
    }
}
