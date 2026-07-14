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

@Test
func promptActionReachabilityMovesTaskChangesAheadWithoutDuplicatingActions() throws {
    let original: [PromptAction] = [
        .init(kind: .returnToActiveTask, title: "Return"),
        .init(kind: .startWorkSprint, title: "Sprint"),
        .init(kind: .startBreak, title: "Break"),
        .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
        .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
        .init(kind: .continueIntentionally, title: "Continue")
    ]

    let layout = PromptActionReachabilityLayout(actions: original)

    #expect(layout.taskChangeActions.map(\.kind) == [.rescheduleTask, .markBlocked])
    #expect(layout.recoveryActions.map(\.kind) == [
        .returnToActiveTask,
        .startWorkSprint,
        .startBreak,
        .continueIntentionally
    ])
    #expect(Set((layout.taskChangeActions + layout.recoveryActions).map(\.id)).count == original.count)
    #expect(layout.taskChangeActions.count + layout.recoveryActions.count == original.count)
}

@Test
func promptActionPublicInterfaceMakesEveryChoiceADirectStableControl() throws {
    let original: [PromptAction] = [
        .init(kind: .returnToActiveTask, title: "Return"),
        .init(kind: .startWorkSprint, title: "Sprint", role: .primary),
        .init(kind: .startBreak, title: "Break"),
        .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
        .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
        .init(kind: .continueIntentionally, title: "Continue")
    ]

    let interface = PromptActionPublicInterface(promptID: "qa-block-1", actions: original)

    #expect(interface.presentation == .directButtonList)
    #expect(interface.controls.map(\.action.kind) == [
        .rescheduleTask,
        .markBlocked,
        .returnToActiveTask,
        .startWorkSprint,
        .startBreak,
        .continueIntentionally
    ])
    #expect(interface.controls.map(\.accessibilityIdentifier) == [
        "today.prompt.qa-block-1.action.reschedule_task",
        "today.prompt.qa-block-1.action.mark_blocked",
        "today.prompt.qa-block-1.action.return_to_active_task",
        "today.prompt.qa-block-1.action.start_work_sprint",
        "today.prompt.qa-block-1.action.start_break",
        "today.prompt.qa-block-1.action.continue_intentionally"
    ])
    #expect(Set(interface.controls.map(\.accessibilityIdentifier)).count == original.count)
}

@Test
func todayPromptActionSurfaceDoesNotVirtualizePublicControls() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let activeRowStart = try #require(source.range(of: "private func activeRow"))
    let actionButtonStart = try #require(source.range(of: "private func promptActionButton"))
    let activeRow = source[activeRowStart.lowerBound..<actionButtonStart.lowerBound]

    #expect(!activeRow.contains("LazyVGrid"))
    #expect(activeRow.contains("ForEach(interface.taskChangeControls)"))
    #expect(activeRow.contains("ForEach(interface.recoveryControls)"))
}

@Test
func todayPresentsPendingDecisionsBeforeTallPlanningSurfacesAndKeepsHistoryInPlace() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/ZoidCoachApp/Views/DashboardView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let todayStart = try #require(source.range(of: "private struct TodayCommandView"))
    let todaySource = source[todayStart.lowerBound...]
    let pendingGuard = try #require(todaySource.range(
        of: "if !model.promptInboxTimeline.awaitingResponse.isEmpty"
    ))
    let decisions = try #require(todaySource.range(of: "TodayPromptInboxLedger()"))
    let planningInvitation = try #require(todaySource.range(of: "PlanningInvitationBanner()"))
    let baseline = try #require(todaySource.range(of: "BaselineObservationView()"))
    let commandOverview = try #require(todaySource.range(of: "TodayDashboardCommandOverview(snapshot: snapshot)"))
    let taskError = try #require(todaySource.range(of: "if let taskError = model.taskCommandError"))
    let historyGuard = try #require(todaySource.range(
        of: "if model.promptInboxTimeline.awaitingResponse.isEmpty"
    ))
    let historyDecisions = try #require(todaySource.range(
        of: "TodayPromptInboxLedger()",
        range: historyGuard.upperBound..<todaySource.endIndex
    ))
    let meetingCandidates = try #require(todaySource.range(of: "MeetingCandidateLedger"))

    #expect(pendingGuard.lowerBound < decisions.lowerBound)
    #expect(decisions.lowerBound < planningInvitation.lowerBound)
    #expect(decisions.lowerBound < baseline.lowerBound)
    #expect(decisions.lowerBound < commandOverview.lowerBound)
    #expect(taskError.lowerBound < historyGuard.lowerBound)
    #expect(historyGuard.lowerBound < historyDecisions.lowerBound)
    #expect(historyDecisions.lowerBound < meetingCandidates.lowerBound)
    #expect(todaySource.components(separatedBy: "TodayPromptInboxLedger()").count - 1 == 2)
}

@Test
func promptBlockFormRejectsEmptyInputAndPreventsDuplicateSubmission() throws {
    var form = PromptTaskBlockFormState()

    #expect(form.beginSubmission() == .failure(.tooShort))
    #expect(form.errorMessage == "Explain the blocker in at least 3 characters.")
    #expect(!form.isSubmitting)

    form.reason = "  Waiting for client approval.  "
    #expect(form.beginSubmission() == .success("Waiting for client approval."))
    #expect(form.isSubmitting)
    #expect(form.beginSubmission() == .failure(.alreadySubmitting))

    form.finishSubmission(error: "The helper is unavailable.")
    #expect(!form.isSubmitting)
    #expect(form.errorMessage == "The helper is unavailable.")

    form.cancel()
    #expect(form == PromptTaskBlockFormState())
}

@Test
func promptBlockFailurePresentationSurvivesInboxRefreshOutcome() {
    let presentation = PromptTaskBlockFailurePresentation(
        taskCommandError: "The blocker was not saved. The last confirmed task and plan state are still shown."
    )

    #expect(presentation.restoring(afterInboxRefreshError: nil) ==
        "The blocker was not saved. The last confirmed task and plan state are still shown.")
    #expect(presentation.restoring(afterInboxRefreshError:
        "Decisions could not be refreshed. The last confirmed inbox remains visible.") ==
        "The blocker was not saved. The last confirmed task and plan state are still shown.")
}

@Test
func promptBlockReasonSuggestionsAreValidAndHistoryFindsThePersistedReason() throws {
    for suggestion in PromptTaskBlockReasonSuggestion.allCases {
        #expect(try PromptTaskBlockReasonState().validated(suggestion.reason).get() == suggestion.reason)
    }

    let episode = promptEpisode(
        id: "blocked-history",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let plan = [
        DailyPlanEntry(
            reminderID: "task-1",
            rank: 0,
            isMainObjective: false,
            estimateMinutes: 30,
            blockedReason: "Waiting for client approval."
        )
    ]

    #expect(PromptTaskBlockedHistoryState.reason(for: episode, in: plan) == "Waiting for client approval.")
    #expect(PromptTaskBlockedHistoryState.reason(for: promptEpisode(id: "other", actions: []), in: plan) == nil)
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
