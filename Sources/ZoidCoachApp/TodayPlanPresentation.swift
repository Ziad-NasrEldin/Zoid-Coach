import Foundation
import ZoidCoachCore

/// Resolves the Day Map from the live local plan while retaining execution
/// details from the last confirmed helper snapshot.
enum TodayPlanPresentation {
    static func rows(
        snapshotRows: [TodayTaskRow],
        livePlan: [DailyPlanEntry],
        reminders: [ReminderTask],
        referenceDate: Date = Date()
    ) -> [TodayTaskRow] {
        let snapshotsByTaskID = snapshotRows.reduce(into: [String: TodayTaskRow]()) {
            $0[$1.taskID] = $1
        }
        let remindersByTaskID = reminders.reduce(into: [String: ReminderTask]()) {
            $0[$1.id] = $1
        }

        return livePlan
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank
                    ? lhs.reminderID < rhs.reminderID
                    : lhs.rank < rhs.rank
            }
            .compactMap { entry in
                if let snapshot = snapshotsByTaskID[entry.reminderID] {
                    return row(snapshot: snapshot, entry: entry)
                }
                guard let reminder = remindersByTaskID[entry.reminderID] else { return nil }
                return row(reminder: reminder, entry: entry, referenceDate: referenceDate)
            }
    }

    private static func row(snapshot: TodayTaskRow, entry: DailyPlanEntry) -> TodayTaskRow {
        TodayTaskRow(
            taskID: snapshot.taskID,
            title: snapshot.title,
            estimateMinutes: presentedEstimate(for: entry),
            dueDate: snapshot.dueDate,
            urgency: snapshot.urgency,
            state: snapshot.state,
            elapsedMinutes: snapshot.elapsedMinutes,
            activeTimeComparison: snapshot.activeTimeComparison,
            completionReason: snapshot.completionReason,
            latestPauseReason: snapshot.latestPauseReason,
            acceptedBreak: snapshot.acceptedBreak,
            sprint: snapshot.sprint,
            isMainObjective: entry.isMainObjective,
            isLocked: snapshot.isLocked,
            isOptional: entry.isOptional,
            blockedReason: entry.blockedReason,
            deferredUntil: entry.deferredUntil,
            learnedEstimateSuggestion: snapshot.learnedEstimateSuggestion
        )
    }

    private static func row(
        reminder: ReminderTask,
        entry: DailyPlanEntry,
        referenceDate: Date
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: reminder.id,
            title: reminder.title,
            estimateMinutes: presentedEstimate(for: entry),
            dueDate: reminder.dueDate,
            urgency: TaskUrgency.resolve(
                dueDate: reminder.dueDate,
                priority: .fromEventKit(reminder.priority),
                referenceDate: referenceDate
            ),
            state: localState(for: entry),
            isMainObjective: entry.isMainObjective,
            isOptional: entry.isOptional,
            blockedReason: entry.blockedReason,
            deferredUntil: entry.deferredUntil
        )
    }

    private static func presentedEstimate(for entry: DailyPlanEntry) -> Int {
        entry.estimateMinutes ?? PlanningCapacityState.unknownEstimatePlaceholderMinutes
    }

    private static func localState(for entry: DailyPlanEntry) -> TaskExecutionState {
        if entry.blockedReason != nil { return .blocked }
        if entry.deferredUntil != nil { return .rescheduled }
        return .ready
    }
}
