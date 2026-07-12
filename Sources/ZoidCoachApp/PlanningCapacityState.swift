import Foundation
import ZoidCoachCore

struct PlanningCapacityState: Equatable, Sendable {
    enum Readiness: Equatable, Sendable {
        case empty
        case missingEstimates(count: Int)
        case overloaded(overByMinutes: Int)
        case realistic
    }

    let plannedMinutes: Int
    let availableMinutes: Int
    let readiness: Readiness
    let suggestedReminderID: String?

    init(entries: [DailyPlanEntry], availableMinutes: Int) {
        let availableMinutes = max(0, availableMinutes)
        let missingEstimateCount = entries.count { $0.estimateMinutes == nil }
        let plannedMinutes = entries.reduce(0) { $0 + max(0, $1.estimateMinutes ?? 0) }

        self.plannedMinutes = plannedMinutes
        self.availableMinutes = availableMinutes

        if entries.isEmpty {
            readiness = .empty
            suggestedReminderID = nil
        } else if missingEstimateCount > 0 {
            readiness = .missingEstimates(count: missingEstimateCount)
            suggestedReminderID = nil
        } else if plannedMinutes > availableMinutes {
            readiness = .overloaded(overByMinutes: plannedMinutes - availableMinutes)
            suggestedReminderID = entries
                .sorted {
                    if $0.rank != $1.rank { return $0.rank > $1.rank }
                    return ($0.estimateMinutes ?? 0) > ($1.estimateMinutes ?? 0)
                }
                .first?
                .reminderID
        } else {
            readiness = .realistic
            suggestedReminderID = nil
        }
    }

    var canApprove: Bool {
        readiness == .realistic
    }
}

struct PlanningCapacityCalculator: Sendable {
    func occupiedMinutes(
        workIntervals: [CalendarInterval],
        commitments: [CalendarCommitment],
        visibleCalendarIdentifiers: Set<String> = []
    ) -> Int {
        let occupiedSeconds = workIntervals.reduce(TimeInterval.zero) { total, workInterval in
            let clipped = commitments
                .filter {
                    !$0.isZoidOwned
                        && (visibleCalendarIdentifiers.isEmpty || visibleCalendarIdentifiers.contains($0.calendarIdentifier))
                        && $0.end > workInterval.start
                        && $0.start < workInterval.end
                }
                .map {
                    DateInterval(
                        start: max($0.start, workInterval.start),
                        end: min($0.end, workInterval.end)
                    )
                }
                .sorted { $0.start < $1.start }

            let merged = clipped.reduce(into: [DateInterval]()) { result, interval in
                if let last = result.last, last.end >= interval.start {
                    result[result.count - 1] = DateInterval(
                        start: last.start,
                        end: max(last.end, interval.end)
                    )
                } else {
                    result.append(interval)
                }
            }
            return total + merged.reduce(0) { $0 + $1.duration }
        }
        return Int(occupiedSeconds / 60)
    }
}
