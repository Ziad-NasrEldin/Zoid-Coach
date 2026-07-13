import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@MainActor
@Test
func dashboardEndWorkdayRechecksPausesAndConfirmsTheExactTask() async throws {
    let active = dashboardSnapshot(taskID: "priority-1", state: .active)
    let ended = dashboardSnapshot(
        taskID: "priority-1",
        state: .paused,
        pauseReason: .endingWorkday,
        hasActiveTask: false
    )
    let client = RecordingDashboardEndWorkdayClient(current: active, applied: ended)
    let flow = DashboardEndWorkdayFlow(client: client)

    #expect(await flow.endWorkday(expectedActiveTaskID: "priority-1"))
    #expect(flow.statusMessage?.contains("Tracked time was preserved") == true)
    #expect(flow.statusMessage?.contains("not marked complete") == true)
    let commands = await client.commands
    #expect(commands.count == 1)
    #expect(commands.first?.0 == .pauseForEndOfDay)
    #expect(commands.first?.1 == "priority-1")
}

@MainActor
@Test
func dashboardEndWorkdayRefusesAStaleConfirmationWithoutMutation() async {
    let changed = dashboardSnapshot(taskID: "priority-2", state: .active)
    let client = RecordingDashboardEndWorkdayClient(current: changed, applied: changed)
    let flow = DashboardEndWorkdayFlow(client: client)

    #expect(await flow.endWorkday(expectedActiveTaskID: "priority-1") == false)
    #expect(flow.statusMessage?.contains("active task changed") == true)
    #expect(await client.commands.isEmpty)
}

@MainActor
@Test
func dashboardEndWorkdayStaysInPlaceWithoutADurableAgentConfirmation() async {
    let unchanged = dashboardSnapshot(taskID: "priority-1", state: .active)
    let client = RecordingDashboardEndWorkdayClient(current: unchanged, applied: unchanged)
    let flow = DashboardEndWorkdayFlow(client: client)

    #expect(await flow.endWorkday(expectedActiveTaskID: "priority-1") == false)
    #expect(flow.statusMessage?.contains("did not confirm") == true)
    #expect(await client.commands.count == 1)
}

private actor RecordingDashboardEndWorkdayClient: DashboardEndWorkdayClient {
    let current: TodaySnapshot
    let applied: TodaySnapshot
    private(set) var commands: [(TaskActivityCommand, String)] = []

    init(current: TodaySnapshot, applied: TodaySnapshot) {
        self.current = current
        self.applied = applied
    }

    func fetchTodaySnapshot() -> TodaySnapshot { current }

    func apply(_ command: TaskActivityCommand, taskID: String) -> TodaySnapshot {
        commands.append((command, taskID))
        return applied
    }
}

private func dashboardSnapshot(
    taskID: String,
    state: TaskExecutionState,
    pauseReason: TaskPauseReason? = nil,
    hasActiveTask: Bool = true
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: "Finish proposal",
        taskRows: [TodayTaskRow(
            taskID: taskID,
            title: "Finish proposal",
            estimateMinutes: 45,
            dueDate: nil,
            urgency: .high,
            state: state,
            elapsedMinutes: 38,
            latestPauseReason: pauseReason,
            isMainObjective: true
        )],
        activeTask: hasActiveTask
            ? ActiveTaskSnapshot(
                taskID: taskID,
                startedAt: Date(timeIntervalSince1970: 1_799_997_720),
                elapsedMinutes: 38
            )
            : nil,
        recommendation: NextTaskRecommendation(
            taskID: taskID,
            sentence: "Continue Finish proposal.",
            reasons: []
        ),
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
        sourceFreshnessExplanation: "Fixture sources"
    )
}
