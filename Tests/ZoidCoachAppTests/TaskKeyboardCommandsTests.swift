import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func keyboardStartUsesOnlyTheExplicitReadyRecommendation() {
    let snapshot = keyboardSnapshot(
        rows: [
            keyboardTask(id: "fallback", title: "Fallback task", state: .ready),
            keyboardTask(id: "recommended", title: "Write proposal", state: .ready),
        ],
        recommendation: .init(
            taskID: "recommended",
            sentence: "Start Write proposal",
            reasons: [.mainObjective]
        )
    )

    let state = TaskKeyboardCommandState(snapshot: snapshot, commandIsPending: false)

    #expect(state.startAction == .start(taskID: "recommended", title: "Write proposal"))
    #expect(state.startAction?.command == .start)
    #expect(state.startLabel == "Start Recommended Task: Write proposal")

    let missing = keyboardSnapshot(
        rows: snapshot.taskRows,
        recommendation: .init(taskID: "missing", sentence: "Unavailable", reasons: [])
    )
    #expect(TaskKeyboardCommandState(snapshot: missing, commandIsPending: false).startAction == nil)
}

@Test
func keyboardStartNeverBypassesAnActiveTaskSwitchConfirmation() {
    let snapshot = keyboardSnapshot(
        rows: [
            keyboardTask(id: "active", title: "Current work", state: .active),
            keyboardTask(id: "recommended", title: "Next work", state: .ready),
        ],
        activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 8),
        recommendation: .init(taskID: "recommended", sentence: "Start Next work", reasons: [])
    )

    let state = TaskKeyboardCommandState(snapshot: snapshot, commandIsPending: false)

    #expect(state.startAction == nil)
    #expect(state.lifecycleAction == .pause(taskID: "active", title: "Current work"))
    #expect(state.lifecycleAction?.command == .pauseDoneForNow)
    #expect(state.lifecycleLabel == "Pause Current Task: Current work")
}

@Test
func keyboardResumeRequiresOneUnambiguousOrdinaryPausedTask() {
    let paused = keyboardTask(
        id: "paused",
        title: "Review budget",
        state: .paused,
        pauseReason: .doneForNow
    )
    let state = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: [paused]),
        commandIsPending: false
    )

    #expect(state.lifecycleAction == .resume(taskID: "paused", title: "Review budget"))
    #expect(state.lifecycleAction?.command == .resume)
    #expect(state.lifecycleLabel == "Resume Paused Task: Review budget")

    let ended = keyboardTask(
        id: "ended",
        title: "Ended task",
        state: .paused,
        pauseReason: .endingWorkday
    )
    let onBreak = keyboardTask(
        id: "break",
        title: "Break task",
        state: .paused,
        pauseReason: .break,
        acceptedBreak: .init(startedAt: Date())
    )
    #expect(TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: [ended, onBreak]),
        commandIsPending: false
    ).lifecycleAction == nil)

    #expect(TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: [paused, keyboardTask(id: "second", title: "Second", state: .paused)]),
        commandIsPending: false
    ).lifecycleAction == nil)
}

@Test
func keyboardCommandsDisableTogetherDuringAnyTaskMutation() {
    let snapshot = keyboardSnapshot(
        rows: [keyboardTask(id: "recommended", title: "Write proposal", state: .ready)],
        recommendation: .init(taskID: "recommended", sentence: "Start", reasons: [])
    )

    let pending = TaskKeyboardCommandState(snapshot: snapshot, commandIsPending: true)

    #expect(pending.startAction == nil)
    #expect(pending.lifecycleAction == nil)
    #expect(TaskKeyboardCommandState(snapshot: nil, commandIsPending: false) == pending)
    #expect(TaskKeyboardCommandState(
        snapshot: snapshot,
        commandIsPending: false,
        commandsAreAvailable: false
    ) == pending)
}

private func keyboardTask(
    id: String,
    title: String,
    state: TaskExecutionState,
    pauseReason: TaskPauseReason? = nil,
    acceptedBreak: AcceptedBreakSnapshot? = nil
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: title,
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: state,
        latestPauseReason: pauseReason,
        acceptedBreak: acceptedBreak
    )
}

private func keyboardSnapshot(
    rows: [TodayTaskRow],
    activeTask: ActiveTaskSnapshot? = nil,
    recommendation: NextTaskRecommendation = .init(
        taskID: nil,
        sentence: "Nothing ready",
        reasons: []
    )
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: nil,
        taskRows: rows,
        activeTask: activeTask,
        recommendation: recommendation,
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(
            isLimited: false,
            explanation: "Fixture coverage",
            lastObservationAt: nil
        ),
        gaming: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 0,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "Finish one priority task",
            confidenceIsLimited: false
        ),
        sourceFreshnessExplanation: "Fixture sources",
        sources: []
    )
}
