import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func estimateProgressExplainsNotStartedAndNormalProgress() {
    let notStarted = TaskEstimateProgress(elapsedMinutes: 0, estimateMinutes: 60)
    #expect(notStarted.phase == .notStarted)
    #expect(notStarted.percent == 0)
    #expect(notStarted.statusLabel == "Not started")

    let underway = TaskEstimateProgress(elapsedMinutes: 25, estimateMinutes: 60)
    #expect(underway.phase == .underway)
    #expect(underway.percent == 42)
    #expect(underway.remainingMinutes == 35)
    #expect(underway.statusLabel == "35 min remaining in estimate")
}

@Test
func estimateProgressCallsOutNearingAndReachedEstimateWithoutJudgment() {
    let nearing = TaskEstimateProgress(elapsedMinutes: 48, estimateMinutes: 60)
    #expect(nearing.phase == .nearingEstimate)
    #expect(nearing.percent == 80)

    let reached = TaskEstimateProgress(elapsedMinutes: 60, estimateMinutes: 60)
    #expect(reached.phase == .nearingEstimate)
    #expect(reached.statusLabel == "Estimate reached")
    #expect(reached.accessibilitySummary == "60 minutes tracked of 60 estimated, estimate reached.")
}

@Test
func estimateProgressReportsOverrunFactuallyAndKeepsTheBarBounded() {
    let progress = TaskEstimateProgress(elapsedMinutes: 75, estimateMinutes: 60)

    #expect(progress.phase == .overEstimate)
    #expect(progress.percent == 125)
    #expect(progress.boundedFraction == 1)
    #expect(progress.overrunMinutes == 15)
    #expect(progress.statusLabel == "15 min over estimate")
}

@Test
func estimateProgressDefensivelyNormalizesInvalidPersistedValues() {
    let progress = TaskEstimateProgress(elapsedMinutes: -4, estimateMinutes: 0)

    #expect(progress.elapsedMinutes == 0)
    #expect(progress.estimateMinutes == 1)
    #expect(progress.percent == 0)
}

@Test
func estimateProgressCanAdvanceFromItsCanonicalSnapshotWhileActive() {
    let progress = TaskEstimateProgress(elapsedMinutes: 59, estimateMinutes: 60)
        .addingElapsedMinutes(2)

    #expect(progress.elapsedMinutes == 61)
    #expect(progress.phase == .overEstimate)
    #expect(progress.statusLabel == "1 min over estimate")
}

@Test
func trackedElapsedTimeRestoresAfterStoreReopenAndProducesTheSameProgress() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("task-estimate-progress-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    do {
        let store = try TaskExecutionStore(databaseURL: url)
        try store.apply(.start, taskID: "task", at: start)
    }

    let reopened = try TaskExecutionStore(databaseURL: url)
    let active = try #require(try reopened.activeTask(now: start.addingTimeInterval(1_500)))
    let progress = TaskEstimateProgress(elapsedMinutes: active.elapsedMinutes, estimateMinutes: 60)

    #expect(active.taskID == "task")
    #expect(active.elapsedMinutes == 25)
    #expect(progress.percent == 42)
    #expect(progress.statusLabel == "35 min remaining in estimate")
}
