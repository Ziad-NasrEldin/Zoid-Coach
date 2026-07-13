import Testing
@testable import ZoidCoachApp

@Test
func selectedPromptShowsApplyingAndExplainsDurableCrossSurfaceRefresh() throws {
    let state = PromptActionPresentation(promptID: "prompt-1", pendingPromptID: "prompt-1", replayed: false)
    #expect(state.isApplying)
    #expect(state.actionsDisabled)
    #expect(state.stateLabel == "APPLYING")
    #expect(try #require(state.progressMessage).contains("Saving this choice once"))
    #expect(try #require(state.progressMessage).contains("refreshing every surface"))
}

@Test
func anotherPendingPromptDisablesActionsWithoutShowingFalseProgress() {
    let state = PromptActionPresentation(promptID: "prompt-2", pendingPromptID: "prompt-1", replayed: true)
    #expect(!state.isApplying)
    #expect(state.actionsDisabled)
    #expect(state.stateLabel == "RETURNED")
    #expect(state.progressMessage == nil)
}

@Test
func idlePromptKeepsItsNormalWaitingState() {
    let state = PromptActionPresentation(promptID: "prompt-1", pendingPromptID: nil, replayed: false)
    #expect(!state.isApplying)
    #expect(!state.actionsDisabled)
    #expect(state.stateLabel == "WAITING")
}
