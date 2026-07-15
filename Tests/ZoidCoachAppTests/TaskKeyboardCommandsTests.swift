import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func keyboardLifecycleShortcutsAreStableAndConflictFree() {
    #expect(TaskKeyboardShortcut.start.rawValue == "s")
    #expect(TaskKeyboardShortcut.pauseOrResume.rawValue == "p")
    #expect(TaskKeyboardShortcut.switchTask.rawValue == "k")
    #expect(TaskKeyboardShortcut.complete.rawValue == "return")
    #expect(Set(TaskKeyboardShortcut.allCases.map(\.rawValue)).count == TaskKeyboardShortcut.allCases.count)
}

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
func keyboardSwitchIsAnExplicitActionThatPreservesTheGenericStartGuard() {
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
    #expect(state.switchAction == .switchTask(
        taskID: "recommended",
        title: "Next work",
        fromTitle: "Current work"
    ))
    #expect(state.switchAction?.command == .start)
    #expect(state.switchLabel == "Switch from Current work to Next work and Preserve Time")
    #expect(state.completeAction == .complete(taskID: "active", title: "Current work"))
    #expect(state.completeAction?.command == .complete)
    #expect(state.completeLabel == "Complete Task: Current work")
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
    #expect(state.completeAction == .complete(taskID: "paused", title: "Review budget"))
    #expect(state.completeAction?.command == .complete)

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
    #expect(TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: [paused, keyboardTask(id: "second", title: "Second", state: .paused)]),
        commandIsPending: false
    ).completeAction == nil)
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
    #expect(pending.switchAction == nil)
    #expect(pending.completeAction == nil)
    #expect(TaskKeyboardCommandState(snapshot: nil, commandIsPending: false) == pending)
    #expect(TaskKeyboardCommandState(
        snapshot: snapshot,
        commandIsPending: false,
        commandsAreAvailable: false
    ) == pending)
}

@Test
func keyboardSwitchFallsBackToOneReadyAlternativeForTheProductionActiveSnapshot() {
    let active = keyboardTask(id: "active", title: "Current", state: .active)
    let ready = keyboardTask(id: "ready", title: "Next", state: .ready)

    let productionSnapshot = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(
            rows: [active, ready],
            activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 4),
            recommendation: .init(
                taskID: "active",
                sentence: "Continue the active task before starting another one.",
                reasons: []
            )
        ),
        commandIsPending: false
    )
    #expect(productionSnapshot.switchAction == .switchTask(
        taskID: "ready",
        title: "Next",
        fromTitle: "Current"
    ))
    #expect(productionSnapshot.switchLabel == "Switch from Current to Next and Preserve Time")
}

@Test
func keyboardSwitchFallbackRejectsZeroOrMultipleReadyAlternatives() {
    let active = keyboardTask(id: "active", title: "Current", state: .active)
    let activeRecommendation = NextTaskRecommendation(
        taskID: "active",
        sentence: "Continue the active task before starting another one.",
        reasons: []
    )

    let noAlternative = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(
            rows: [active],
            activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 4),
            recommendation: activeRecommendation
        ),
        commandIsPending: false
    )
    #expect(noAlternative.switchAction == nil)

    let ambiguousAlternatives = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(
            rows: [
                active,
                keyboardTask(id: "first", title: "First", state: .ready),
                keyboardTask(id: "second", title: "Second", state: .ready),
            ],
            activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 4),
            recommendation: activeRecommendation
        ),
        commandIsPending: false
    )
    #expect(ambiguousAlternatives.switchAction == nil)
    #expect(ambiguousAlternatives.switchLabel == "Switch to Recommended Task")
}

@Test
func keyboardSwitchRequiresAnActiveTaskAndAResolvableReadyTarget() {
    let active = keyboardTask(id: "active", title: "Current", state: .active)
    let ready = keyboardTask(id: "ready", title: "Next", state: .ready)

    let noActive = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(
            rows: [ready],
            recommendation: .init(taskID: "ready", sentence: "Start Next", reasons: [])
        ),
        commandIsPending: false
    )
    #expect(noActive.switchAction == nil)

    let missingRecommendation = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(
            rows: [active, ready],
            activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 4),
            recommendation: .init(taskID: "missing", sentence: "Unavailable", reasons: [])
        ),
        commandIsPending: false
    )
    #expect(missingRecommendation.switchAction == nil)
    #expect(missingRecommendation.switchLabel == "Switch to Recommended Task")
}

@Test
func keyboardCompleteRequiresOneCurrentActiveOrOrdinaryPausedTask() {
    let empty = TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: []),
        commandIsPending: false
    )
    #expect(empty.completeAction == nil)
    #expect(empty.completeLabel == "Complete Current Task")

    let ended = keyboardTask(
        id: "ended",
        title: "Ended task",
        state: .paused,
        pauseReason: .endingWorkday
    )
    #expect(TaskKeyboardCommandState(
        snapshot: keyboardSnapshot(rows: [ended]),
        commandIsPending: false
    ).completeAction == nil)
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
