import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Today open-ended elapsed time")
struct TodayDashboardCommandOverviewTests {
    @Test("full-estimate sprint names the exact confident estimate")
    func fullEstimateSprintUsesConfidentEstimate() throws {
        let option = try #require(FullEstimateSprintOption(
            estimateMinutes: 90,
            estimateIsUncertain: false
        ))

        #expect(option.durationMinutes == 90)
        #expect(option.menuTitle == "90-minute full estimate")
        #expect(option.accessibilityHint.contains("full 90-minute estimate"))
    }

    @Test("full-estimate sprint is unavailable for missing or uncertain estimates")
    func fullEstimateSprintRequiresConfidentEstimate() {
        #expect(FullEstimateSprintOption(
            estimateMinutes: nil,
            estimateIsUncertain: false
        ) == nil)
        #expect(FullEstimateSprintOption(
            estimateMinutes: 45,
            estimateIsUncertain: true
        ) == nil)
    }

    @Test("active open-ended time advances from the canonical open interval")
    func activeOpenEndedTimeAdvancesFromCurrentDate() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = taskRow(elapsedMinutes: 12)
        let activeTask = ActiveTaskSnapshot(
            taskID: task.taskID,
            startedAt: confirmedAt.addingTimeInterval(-12 * 60),
            elapsedMinutes: 12
        )

        let presentation = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: activeTask,
            snapshotConfirmedAt: confirmedAt,
            currentDate: confirmedAt.addingTimeInterval(125)
        ))

        #expect(presentation.elapsedMinutes == 14)
        #expect(presentation.isLive)
        #expect(presentation.displayText == "14 MIN ELAPSED · LIVE")
        #expect(presentation.accessibilityLabel == "Open-ended session, 14 minutes elapsed, updating while active.")
    }

    @Test("elapsed time preserves earlier intervals while the current interval advances")
    func elapsedTimePreservesEarlierIntervals() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = taskRow(elapsedMinutes: 25)
        let activeTask = ActiveTaskSnapshot(
            taskID: task.taskID,
            startedAt: confirmedAt.addingTimeInterval(-5 * 60),
            elapsedMinutes: 25
        )

        let presentation = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: activeTask,
            snapshotConfirmedAt: confirmedAt,
            currentDate: confirmedAt.addingTimeInterval(3 * 60)
        ))

        #expect(presentation.elapsedMinutes == 28)
    }

    @Test("clock rollback and incomplete active metadata never reduce confirmed elapsed time")
    func clockRollbackAndIncompleteMetadataDoNotRegressElapsedTime() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = taskRow(elapsedMinutes: 9)
        let activeTask = ActiveTaskSnapshot(
            taskID: task.taskID,
            startedAt: confirmedAt.addingTimeInterval(-9 * 60),
            elapsedMinutes: 9
        )

        let rolledBack = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: activeTask,
            snapshotConfirmedAt: confirmedAt,
            currentDate: confirmedAt.addingTimeInterval(-20 * 60)
        ))
        let missingStart = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: .init(taskID: task.taskID, startedAt: nil, elapsedMinutes: 9),
            snapshotConfirmedAt: confirmedAt,
            currentDate: confirmedAt.addingTimeInterval(5 * 60)
        ))
        let mismatchedTask = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: .init(taskID: "other", startedAt: confirmedAt, elapsedMinutes: 0),
            snapshotConfirmedAt: confirmedAt,
            currentDate: confirmedAt.addingTimeInterval(5 * 60)
        ))

        #expect(rolledBack.elapsedMinutes == 9)
        #expect(rolledBack.isLive)
        #expect(missingStart.elapsedMinutes == 9)
        #expect(!missingStart.isLive)
        #expect(missingStart.displayText == "9 MIN ELAPSED · LAST REFRESH")
        #expect(missingStart.accessibilityLabel == "Open-ended session, 9 minutes elapsed at the last refresh.")
        #expect(mismatchedTask.elapsedMinutes == 9)
        #expect(!mismatchedTask.isLive)
    }

    @Test("only active open-ended timing modes receive the live indicator")
    func indicatorExcludesPausedAndBoundedSessions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let paused = taskRow(state: .paused, elapsedMinutes: 5)
        let bounded = taskRow(
            elapsedMinutes: 5,
            sprint: .init(
                durationMinutes: 20,
                elapsedSeconds: 300,
                remainingSeconds: 900,
                state: .active,
                observedAt: now
            )
        )
        let continued = taskRow(
            elapsedMinutes: 20,
            sprint: .init(
                durationMinutes: 20,
                elapsedSeconds: 1_200,
                remainingSeconds: 0,
                state: .continuedOpenEnded,
                observedAt: now
            )
        )

        #expect(OpenEndedElapsedTimePresentation(
            task: paused,
            activeTask: nil,
            snapshotConfirmedAt: now,
            currentDate: now
        ) == nil)
        #expect(OpenEndedElapsedTimePresentation(
            task: bounded,
            activeTask: nil,
            snapshotConfirmedAt: now,
            currentDate: now
        ) == nil)
        #expect(OpenEndedElapsedTimePresentation(
            task: continued,
            activeTask: nil,
            snapshotConfirmedAt: now,
            currentDate: now
        )?.elapsedMinutes == 20)
    }

    @Test("one minute uses singular accessible wording")
    func oneMinuteUsesSingularAccessibleWording() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = taskRow(elapsedMinutes: 1)
        let presentation = try #require(OpenEndedElapsedTimePresentation(
            task: task,
            activeTask: .init(
                taskID: task.taskID,
                startedAt: now.addingTimeInterval(-60),
                elapsedMinutes: 1
            ),
            snapshotConfirmedAt: now,
            currentDate: now
        ))

        #expect(presentation.accessibilityLabel == "Open-ended session, 1 minute elapsed, updating while active.")
    }
}

private func taskRow(
    state: TaskExecutionState = .active,
    elapsedMinutes: Int,
    sprint: SprintSnapshot? = nil
) -> TodayTaskRow {
    .init(
        taskID: "focus",
        title: "Write proposal",
        estimateMinutes: 60,
        dueDate: nil,
        urgency: .medium,
        state: state,
        elapsedMinutes: elapsedMinutes,
        sprint: sprint,
        isMainObjective: true
    )
}
