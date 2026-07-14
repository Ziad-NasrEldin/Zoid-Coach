import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Today plan presentation")
struct TodayPlanPresentationTests {
    @Test("a newly planned Reminder replaces a stale zero-block helper snapshot")
    func newlyPlannedReminderAppearsBeforeTheHelperSnapshotRefreshes() {
        let task = reminder(id: "proposal", title: "Protect the local approved plan")
        let plan = [DailyPlanEntry(
            reminderID: task.id,
            rank: 1,
            isMainObjective: true,
            estimateMinutes: nil
        )]

        let rows = TodayPlanPresentation.rows(
            snapshotRows: [],
            livePlan: plan,
            reminders: [task],
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(rows.map(\.taskID) == ["proposal"])
        #expect(rows.map(\.title) == ["Protect the local approved plan"])
        #expect(rows.map(\.estimateMinutes) == [PlanningCapacityState.unknownEstimatePlaceholderMinutes])
        #expect(rows.map(\.isMainObjective) == [true])
    }

    @Test("a locally removed task disappears even while the helper snapshot is stale")
    func removedTaskDoesNotRemainAsAStalePlannedBlock() {
        let rows = TodayPlanPresentation.rows(
            snapshotRows: [snapshotRow(id: "removed", title: "Already removed")],
            livePlan: [],
            reminders: [reminder(id: "removed", title: "Already removed")],
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(rows.isEmpty)
    }

    @Test("live plan edits override stale helper plan fields without losing execution state")
    func livePlanFieldsWinWhileExecutionStateRemainsAuthoritative() throws {
        let snapshot = TodayTaskRow(
            taskID: "active",
            title: "Current task",
            estimateMinutes: 20,
            dueDate: nil,
            urgency: .low,
            state: .active,
            elapsedMinutes: 7,
            isMainObjective: false,
            isOptional: false
        )
        let plan = [DailyPlanEntry(
            reminderID: "active",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: 45,
            isOptional: false,
            blockedReason: nil,
            deferredUntil: nil
        )]

        let row = try #require(TodayPlanPresentation.rows(
            snapshotRows: [snapshot],
            livePlan: plan,
            reminders: [],
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        ).first)

        #expect(row.state == .active)
        #expect(row.elapsedMinutes == 7)
        #expect(row.estimateMinutes == 45)
        #expect(row.isMainObjective)
    }

    private func reminder(id: String, title: String) -> ReminderTask {
        ReminderTask(
            id: id,
            title: title,
            listID: "work",
            listName: "Work",
            dueDate: nil,
            priority: 0,
            notes: nil,
            modificationDate: nil
        )
    }

    private func snapshotRow(id: String, title: String) -> TodayTaskRow {
        TodayTaskRow(
            taskID: id,
            title: title,
            estimateMinutes: 30,
            dueDate: nil,
            urgency: .low,
            state: .ready
        )
    }
}
