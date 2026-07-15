import Foundation
import ZoidCoachCore

struct DailyReviewCorrectionImpact: Equatable {
    struct ClassificationMove: Equatable {
        let from: BehaviorClassification
        let to: BehaviorClassification
        let minutes: Int
    }

    enum TaskAlignmentChange: Equatable {
        case attached(minutes: Int)
        case removed(minutes: Int)
        case unchanged(minutes: Int)
    }

    enum ReviewStatementChange: Equatable {
        case changed
        case unchanged
    }

    let classificationMove: ClassificationMove?
    let taskAlignmentChange: TaskAlignmentChange
    let reviewStatementChange: ReviewStatementChange

    init?(
        before: DailyReviewSnapshot,
        after: DailyReviewSnapshot,
        affectedSession: DailyReviewSession,
        requestedClassification: BehaviorClassification
    ) {
        guard before.sourceDay == after.sourceDay,
              before.sourceDay == affectedSession.sourceDay
        else { return nil }

        classificationMove = Self.classificationMove(
            before: before,
            after: after,
            from: affectedSession.classification,
            to: requestedClassification
        )

        let beforeAlignedMinutes = Self.alignedMinutes(
            in: before,
            overlapping: affectedSession
        )
        let afterAlignedMinutes = Self.alignedMinutes(
            in: after,
            overlapping: affectedSession
        )
        if afterAlignedMinutes > beforeAlignedMinutes {
            taskAlignmentChange = .attached(minutes: afterAlignedMinutes - beforeAlignedMinutes)
        } else if afterAlignedMinutes < beforeAlignedMinutes {
            taskAlignmentChange = .removed(minutes: beforeAlignedMinutes - afterAlignedMinutes)
        } else {
            taskAlignmentChange = .unchanged(minutes: afterAlignedMinutes)
        }

        reviewStatementChange = before.hypothesis == after.hypothesis ? .unchanged : .changed

        let alignmentChanged = beforeAlignedMinutes != afterAlignedMinutes
        let statementChanged = before.hypothesis != after.hypothesis
        guard classificationMove != nil || alignmentChanged || statementChanged else { return nil }
    }

    var classificationDetail: String? {
        guard let classificationMove else { return nil }
        return "Moved \(classificationMove.minutes) min from \(classificationMove.from.rawValue.capitalized) to \(classificationMove.to.rawValue.capitalized)."
    }

    var taskAlignmentDetail: String {
        switch taskAlignmentChange {
        case let .attached(minutes):
            return "Task alignment attached for \(minutes) min."
        case let .removed(minutes):
            return "Task alignment removed from \(minutes) min."
        case let .unchanged(minutes):
            return "Task alignment unchanged at \(minutes) min."
        }
    }

    var reviewStatementDetail: String {
        switch reviewStatementChange {
        case .changed:
            return "The review statement changed after recalculation."
        case .unchanged:
            return "The review statement did not change."
        }
    }

    var accessibilitySummary: String {
        [classificationDetail, taskAlignmentDetail, reviewStatementDetail]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func classificationMove(
        before: DailyReviewSnapshot,
        after: DailyReviewSnapshot,
        from: BehaviorClassification,
        to: BehaviorClassification
    ) -> ClassificationMove? {
        guard from != to else { return nil }
        let removed = max(0, total(for: from, in: before) - total(for: from, in: after))
        let added = max(0, total(for: to, in: after) - total(for: to, in: before))
        let moved = min(removed, added)
        guard moved > 0 else { return nil }
        return ClassificationMove(from: from, to: to, minutes: moved)
    }

    private static func total(
        for classification: BehaviorClassification,
        in snapshot: DailyReviewSnapshot
    ) -> Int {
        snapshot.totals.first { $0.classification == classification }?.minutes ?? 0
    }

    private static func alignedMinutes(
        in snapshot: DailyReviewSnapshot,
        overlapping affectedSession: DailyReviewSession
    ) -> Int {
        let alignedSeconds = snapshot.sessions.reduce(0.0) { result, session in
            guard session.taskID != nil else { return result }
            let overlapStart = max(session.start, affectedSession.start)
            let overlapEnd = min(session.end, affectedSession.end)
            return result + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        guard alignedSeconds > 0 else { return 0 }
        return max(1, Int((alignedSeconds / 60).rounded(.up)))
    }
}
