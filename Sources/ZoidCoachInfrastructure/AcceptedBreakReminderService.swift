import Foundation
import ZoidCoachCore

public protocol AcceptedBreakReminderScheduling: Sendable {
    func scheduleAcceptedBreakEnd(
        taskID: String,
        taskTitle: String,
        startedAt: Date,
        deliveryDate: Date
    ) async throws -> Bool

    func cancelAcceptedBreakEnds(taskID: String) async
}

public struct AcceptedBreakReminderReconciliation: Equatable, Sendable {
    public let scheduledTaskIDs: [String]
    public let cancelledTaskIDs: [String]
    public let failedTaskIDs: [String]

    public init(scheduledTaskIDs: [String], cancelledTaskIDs: [String], failedTaskIDs: [String]) {
        self.scheduledTaskIDs = scheduledTaskIDs
        self.cancelledTaskIDs = cancelledTaskIDs
        self.failedTaskIDs = failedTaskIDs
    }
}

public struct AcceptedBreakReminderService: Sendable {
    private let scheduler: any AcceptedBreakReminderScheduling

    public init(scheduler: any AcceptedBreakReminderScheduling) {
        self.scheduler = scheduler
    }

    @discardableResult
    public func reconcile(
        taskRows: [TodayTaskRow],
        now: Date = Date()
    ) async -> AcceptedBreakReminderReconciliation {
        var scheduled: [String] = []
        var cancelled: [String] = []
        var failed: [String] = []

        for row in taskRows {
            if let acceptedBreak = row.acceptedBreak {
                let deliveryDate = max(
                    now.addingTimeInterval(1),
                    acceptedBreak.startedAt.addingTimeInterval(TimeInterval(acceptedBreak.durationMinutes * 60))
                )
                do {
                    if try await scheduler.scheduleAcceptedBreakEnd(
                        taskID: row.taskID,
                        taskTitle: row.title,
                        startedAt: acceptedBreak.startedAt,
                        deliveryDate: deliveryDate
                    ) {
                        scheduled.append(row.taskID)
                    }
                } catch {
                    failed.append(row.taskID)
                }
            } else if row.latestPauseReason == .break {
                await scheduler.cancelAcceptedBreakEnds(taskID: row.taskID)
                cancelled.append(row.taskID)
            }
        }

        return AcceptedBreakReminderReconciliation(
            scheduledTaskIDs: scheduled,
            cancelledTaskIDs: cancelled,
            failedTaskIDs: failed
        )
    }
}
