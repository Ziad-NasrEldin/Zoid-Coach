import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func promptTaskBlockRequestRequiresExplicitActionAndTaskIdentity() throws {
    let valid = promptEpisode(
        id: "valid",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let missingTask = promptEpisode(
        id: "missing-task",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")]
    )
    let wrongAction = promptEpisode(
        id: "wrong-action",
        actions: [.init(kind: .pauseTask, title: "Pause")],
        payload: ["taskID": "task-1"]
    )

    let request = try #require(PromptTaskBlockRequest(episode: valid))
    #expect(request.taskID == "task-1")
    #expect(request.taskTitle == "Prepare release")
    #expect(PromptTaskBlockRequest(episode: missingTask) == nil)
    #expect(PromptTaskBlockRequest(episode: wrongAction) == nil)
}

@Test
func promptTaskBlockReasonTrimsMeaningfulCopyAndRejectsUnsafeLengths() throws {
    let state = PromptTaskBlockReasonState()

    #expect(try state.validated("  Waiting for client approval.  ").get() == "Waiting for client approval.")
    #expect(state.validated("no") == .failure(.tooShort))
    #expect(state.validated(String(repeating: "x", count: 241)) == .failure(.tooLong))
    #expect(try state.validated(String(repeating: "x", count: 240)).get().count == 240)
}

private func promptEpisode(
    id: String,
    actions: [PromptAction],
    payload: [String: String] = [:]
) -> PromptEpisode {
    PromptEpisode(
        id: id,
        decisionKey: "block:\(id)",
        type: "GAMING_DRIFT",
        state: .presented,
        title: "Task needs attention",
        summary: "Choose what should happen next.",
        actions: actions,
        payload: payload,
        createdAt: Date()
    )
}
