import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func openEndedActiveCommitmentNamesItsManualTimingContract() throws {
    let presentation = try #require(ActiveCommitmentPresentation(task: activeCommitmentTask(elapsedMinutes: 12)))

    #expect(presentation.modeLabel == "OPEN-ENDED SESSION")
    #expect(presentation.dashboardHeading == "ACTIVE COMMITMENT · OPEN-ENDED · 12 MIN TRACKED")
    #expect(presentation.menuStatus == "Active · Open-ended · 12 min tracked")
    #expect(presentation.detail.contains("Pause or Complete"))
    #expect(presentation.detail.contains("No automatic end time"))
    #expect(presentation.accessibilitySummary.contains("Write proposal"))
}

@Test
func boundedCommitmentUsesCurrentRemainingTimeAndPreservesIncompleteMeaning() throws {
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let task = activeCommitmentTask(
        elapsedMinutes: 7,
        sprint: SprintSnapshot(
            durationMinutes: 20,
            elapsedSeconds: 420,
            remainingSeconds: 780,
            state: .active,
            observedAt: observedAt
        )
    )
    let presentation = try #require(ActiveCommitmentPresentation(
        task: task,
        at: observedAt.addingTimeInterval(61)
    ))

    #expect(presentation.modeLabel == "20-MINUTE SPRINT")
    #expect(presentation.dashboardHeading == "ACTIVE COMMITMENT · 12 MIN LEFT · 7 MIN TRACKED")
    #expect(presentation.menuStatus == "Active sprint · 12 min left · 7 min tracked")
    #expect(presentation.detail.contains("stays incomplete"))
}

@Test
func continuedSprintBecomesTruthfullyOpenEndedEverywhere() throws {
    let task = activeCommitmentTask(
        elapsedMinutes: 26,
        sprint: SprintSnapshot(
            durationMinutes: 20,
            elapsedSeconds: 1_560,
            remainingSeconds: 0,
            state: .continuedOpenEnded
        )
    )
    let presentation = try #require(ActiveCommitmentPresentation(task: task))

    #expect(presentation.modeLabel == "OPEN-ENDED CONTINUATION")
    #expect(presentation.dashboardHeading.contains("OPEN-ENDED"))
    #expect(presentation.menuStatus.contains("Open-ended continuation"))
    #expect(presentation.detail.contains("without an automatic end time"))
}

@Test
func inactiveRowsDoNotClaimAnActiveTimingContract() {
    let paused = TodayTaskRow(
        taskID: "proposal",
        title: "Write proposal",
        estimateMinutes: 45,
        dueDate: nil,
        urgency: .low,
        state: .paused,
        elapsedMinutes: 12
    )

    #expect(ActiveCommitmentPresentation(task: paused) == nil)
}

private func activeCommitmentTask(
    elapsedMinutes: Int,
    sprint: SprintSnapshot? = nil
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: "proposal",
        title: "Write proposal",
        estimateMinutes: 45,
        dueDate: nil,
        urgency: .low,
        state: .active,
        elapsedMinutes: elapsedMinutes,
        sprint: sprint,
        isMainObjective: true
    )
}
