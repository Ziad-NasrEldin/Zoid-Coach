import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test func menuBarStateDistinguishesNeutralAttentionActiveAndPaused() {
    #expect(MenuBarCoachState(snapshot: nil).tone == .neutral)

    let healthy = menuSnapshot(sources: [
        SourceFreshnessSnapshot(sourceID: "agent", state: "running", detail: "Agent is current", lastUpdatedAt: nil)
    ])
    #expect(MenuBarCoachState(snapshot: healthy).tone == .neutral)

    let attention = menuSnapshot(sources: [
        SourceFreshnessSnapshot(sourceID: "screenwatch", state: "limited", detail: "No recent activity", lastUpdatedAt: nil)
    ])
    let attentionState = MenuBarCoachState(snapshot: attention)
    #expect(attentionState.tone == .attention)
    #expect(attentionState.attentionDetail == "screenwatch: No recent activity")

    let activeRow = menuTask(id: "active", title: "Write proposal", state: .active, elapsedMinutes: 12)
    let active = menuSnapshot(rows: [activeRow], activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 12), sources: attention.sources ?? [])
    let activeState = MenuBarCoachState(snapshot: active)
    #expect(activeState.tone == .active)
    #expect(activeState.primaryTask?.title == "Write proposal")
    #expect(activeState.taskStatus == "Active · 12 min tracked")

    let paused = menuSnapshot(rows: [menuTask(id: "paused", title: "Review budget", state: .paused, pauseReason: .doneForNow)])
    let pausedState = MenuBarCoachState(snapshot: paused)
    #expect(pausedState.tone == .paused)
    #expect(pausedState.taskStatus == "Paused because you are done for now")
}

@Test func menuBarChoosesExplicitRecommendationBeforeFallbackReadyTask() {
    let rows = [
        menuTask(id: "fallback", title: "Fallback", state: .ready),
        menuTask(id: "recommended", title: "Recommended", state: .ready)
    ]
    let snapshot = menuSnapshot(
        rows: rows,
        recommendation: NextTaskRecommendation(
            taskID: "recommended",
            sentence: "Start Recommended",
            reasons: [.mainObjective]
        )
    )

    #expect(MenuBarCoachState(snapshot: snapshot).recommendedTask?.taskID == "recommended")
}

@Test func menuBarDoesNotOfferOptionalOrUnavailableRecommendationAsFallback() {
    let rows = [
        menuTask(id: "optional", title: "Optional", state: .ready, isOptional: true),
        menuTask(id: "blocked", title: "Blocked", state: .blocked)
    ]
    let snapshot = menuSnapshot(
        rows: rows,
        recommendation: NextTaskRecommendation(taskID: "missing", sentence: "Unavailable", reasons: [])
    )

    #expect(MenuBarCoachState(snapshot: snapshot).recommendedTask == nil)
}

@MainActor
@Test func menuBarControllerRefreshesAppliesAndPreservesLastConfirmedStateOnFailure() async {
    let ready = menuSnapshot(rows: [menuTask(id: "task", title: "Task", state: .ready)])
    let active = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active)],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 0)
    )
    let client = RecordingMenuBarTodayClient(fetchResult: .success(ready), applyResults: [.success(active), .failure(MenuBarClientError.failed)])
    let controller = MenuBarCoachController(client: client)

    await controller.refresh()
    #expect(controller.state.recommendedTask?.taskID == "task")

    await controller.apply(.start, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage == nil)

    await controller.apply(.pauseDoneForNow, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage?.contains("last confirmed state") == true)

    let commands = await client.commands
    #expect(commands.map(\.0) == [.start, .pauseDoneForNow])
    #expect(commands.map(\.1) == ["task", "task"])
}

private actor RecordingMenuBarTodayClient: MenuBarTodayClient {
    let fetchResult: Result<TodaySnapshot, Error>
    var applyResults: [Result<TodaySnapshot, Error>]
    private(set) var commands: [(TaskActivityCommand, String)] = []

    init(fetchResult: Result<TodaySnapshot, Error>, applyResults: [Result<TodaySnapshot, Error>]) {
        self.fetchResult = fetchResult
        self.applyResults = applyResults
    }

    func fetchTodaySnapshot() async throws -> TodaySnapshot { try fetchResult.get() }

    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot {
        commands.append((command, taskID))
        guard !applyResults.isEmpty else { throw MenuBarClientError.failed }
        return try applyResults.removeFirst().get()
    }
}

private enum MenuBarClientError: Error { case failed }

private func menuTask(
    id: String,
    title: String,
    state: TaskExecutionState,
    elapsedMinutes: Int = 0,
    pauseReason: TaskPauseReason? = nil,
    isOptional: Bool = false
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: title,
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: state,
        elapsedMinutes: elapsedMinutes,
        latestPauseReason: pauseReason,
        isOptional: isOptional
    )
}

private func menuSnapshot(
    rows: [TodayTaskRow] = [],
    activeTask: ActiveTaskSnapshot? = nil,
    recommendation: NextTaskRecommendation = .init(taskID: nil, sentence: "Nothing ready", reasons: []),
    sources: [SourceFreshnessSnapshot] = []
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: rows.first(where: \.isMainObjective)?.title,
        taskRows: rows,
        activeTask: activeTask,
        recommendation: recommendation,
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(isLimited: sources.contains { $0.state == "limited" }, explanation: "Fixture coverage", lastObservationAt: nil),
        gaming: GamingStatus(budgetMinutes: 60, usedMinutes: 0, unlockedRemainingMinutes: 0, nextUnlockReason: "Finish one priority task", confidenceIsLimited: false),
        sourceFreshnessExplanation: "Fixture sources",
        sources: sources
    )
}
