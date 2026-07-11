import Foundation

public struct CalendarInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(end, start)
    }

    public var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}

public struct SchedulableTask: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let durationMinutes: Int

    public init(id: String, title: String, durationMinutes: Int) {
        self.id = id
        self.title = title
        self.durationMinutes = max(1, durationMinutes)
    }
}

public struct ScheduledTaskBlock: Equatable, Sendable, Identifiable {
    public let taskID: String
    public let start: Date
    public let end: Date

    public var id: String { "\(taskID)-\(start.timeIntervalSince1970)" }
}

public struct CalendarScheduleResult: Equatable, Sendable {
    public let blocks: [ScheduledTaskBlock]
    public let unscheduledTaskIDs: [String]

    public init(blocks: [ScheduledTaskBlock], unscheduledTaskIDs: [String]) {
        self.blocks = blocks
        self.unscheduledTaskIDs = unscheduledTaskIDs
    }
}

public struct CalendarBlockScheduler: Sendable {
    public init() {}

    public func schedule(
        tasks: [SchedulableTask],
        availableIntervals: [CalendarInterval],
        transitionMinutes: Int,
        preferredInterval: CalendarInterval? = nil
    ) -> CalendarScheduleResult {
        let transition = TimeInterval(max(0, transitionMinutes) * 60)
        var intervals = availableIntervals
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                if let preferredInterval {
                    let lhsPreferred = lhs.end > preferredInterval.start && lhs.start < preferredInterval.end
                    let rhsPreferred = rhs.end > preferredInterval.start && rhs.start < preferredInterval.end
                    if lhsPreferred != rhsPreferred { return lhsPreferred }
                }
                return lhs.start < rhs.start
            }
        var blocks: [ScheduledTaskBlock] = []
        var unscheduledTaskIDs: [String] = []

        for task in tasks {
            let taskDuration = TimeInterval(task.durationMinutes * 60)
            guard let index = intervals.firstIndex(where: { interval in
                interval.end.timeIntervalSince(interval.start) >= taskDuration
            }) else {
                unscheduledTaskIDs.append(task.id)
                continue
            }

            let interval = intervals[index]
            let end = interval.start.addingTimeInterval(taskDuration)
            blocks.append(ScheduledTaskBlock(taskID: task.id, start: interval.start, end: end))
            let nextStart = end.addingTimeInterval(transition)
            if nextStart < interval.end {
                intervals[index] = CalendarInterval(start: nextStart, end: interval.end)
            } else {
                intervals.remove(at: index)
            }
        }

        return CalendarScheduleResult(blocks: blocks, unscheduledTaskIDs: unscheduledTaskIDs)
    }
}
