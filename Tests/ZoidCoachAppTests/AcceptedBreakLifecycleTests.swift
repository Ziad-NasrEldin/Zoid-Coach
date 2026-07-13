import Foundation
import Testing
import ZoidCoachCore
import ZoidCoachInfrastructure
@testable import ZoidCoachApp

@Test
func acceptedBreakPersistsItsStartAndEndsWhenWorkResumes() throws {
    let fixture = try BreakFixture()
    let started = Date(timeIntervalSince1970: 1_800_000_000)
    try fixture.store.apply(.start, taskID: "priority", at: started)
    try fixture.store.apply(.pauseForBreak, taskID: "priority", at: started.addingTimeInterval(120))

    let paused = try #require(fixture.store.snapshot(for: ["priority"], now: started.addingTimeInterval(180))["priority"])
    let acceptedBreak = try #require(paused.acceptedBreak)
    #expect(paused.state == .paused)
    #expect(paused.latestPauseReason == .break)
    #expect(acceptedBreak.startedAt == started.addingTimeInterval(120))
    #expect(acceptedBreak.remainingSeconds(at: started.addingTimeInterval(180)) == 840)

    let reopened = try TaskExecutionStore(databaseURL: fixture.databaseURL)
    let restored = try #require(reopened.snapshot(for: ["priority"], now: started.addingTimeInterval(1_020))["priority"])
    #expect(restored.acceptedBreak?.hasEnded(at: started.addingTimeInterval(1_020)) == true)

    try reopened.apply(.resume, taskID: "priority", at: started.addingTimeInterval(1_030))
    let resumed = try #require(reopened.snapshot(for: ["priority"], now: started.addingTimeInterval(1_031))["priority"])
    #expect(resumed.state == .active)
    #expect(resumed.acceptedBreak == nil)
}

@Test
func menuBarExplainsLiveAndCompletedAcceptedBreaks() {
    let started = Date(timeIntervalSince1970: 1_800_000_000)
    let row = TodayTaskRow(
        taskID: "priority",
        title: "Write proposal",
        estimateMinutes: 45,
        dueDate: nil,
        urgency: .high,
        state: .paused,
        latestPauseReason: .break,
        acceptedBreak: AcceptedBreakSnapshot(startedAt: started)
    )
    let state = MenuBarCoachState(snapshot: breakSnapshot(row: row))

    #expect(state.taskStatus(at: started.addingTimeInterval(60)) == "Accepted break · 14 min left")
    #expect(state.taskStatus(at: started.addingTimeInterval(901)) == "Accepted break ended · Resume when ready")
}

private struct BreakFixture {
    let directory: URL
    let databaseURL: URL
    let store: TaskExecutionStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directory.appendingPathComponent("zoid.sqlite")
        store = try TaskExecutionStore(databaseURL: databaseURL)
    }
}

private func breakSnapshot(row: TodayTaskRow) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: row.title,
        taskRows: [row],
        activeTask: nil,
        recommendation: NextTaskRecommendation(taskID: nil, sentence: "Resume after the break", reasons: []),
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(isLimited: false, explanation: "Fixture", lastObservationAt: nil),
        gaming: GamingStatus(budgetMinutes: 60, usedMinutes: 0, unlockedRemainingMinutes: 0, nextUnlockReason: "None", confidenceIsLimited: false),
        sourceFreshnessExplanation: "Fixture",
        sources: []
    )
}
