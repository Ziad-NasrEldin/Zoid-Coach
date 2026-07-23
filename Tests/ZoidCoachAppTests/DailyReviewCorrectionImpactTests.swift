import Foundation
import Testing
import ZoidCoachCore
@testable import ZoidCoachApp

@Test("classification impact uses persisted total deltas instead of the requested session duration")
func correctionImpactUsesActualClassificationDelta() throws {
    let affected = reviewSession(classification: .gaming, minutes: 60)
    let before = reviewSnapshot(
        sessions: [affected],
        totals: [.init(classification: .gaming, minutes: 40), .init(classification: .work, minutes: 10)],
        hypothesis: "Gaming was the largest covered category."
    )
    let after = reviewSnapshot(
        sessions: [reviewSession(classification: .work, minutes: 60)],
        totals: [.init(classification: .gaming, minutes: 20), .init(classification: .work, minutes: 30)],
        hypothesis: "Gaming was the largest covered category."
    )

    let impact = try #require(DailyReviewCorrectionImpact(
        before: before,
        after: after,
        affectedSession: affected,
        requestedClassification: .work
    ))

    #expect(impact.classificationMove == .init(from: .gaming, to: .work, minutes: 20))
    #expect(impact.taskAlignmentChange == .unchanged(minutes: 0))
    #expect(impact.reviewStatementChange == .unchanged)
    #expect(impact.classificationDetail == "Moved 20 min from Gaming to Work.")
}

@Test("task alignment attachment reports only the persisted overlapping minutes")
func correctionImpactReportsAttachedTaskAlignment() throws {
    let affected = reviewSession(classification: .work, minutes: 30)
    let before = reviewSnapshot(sessions: [affected], totals: [.init(classification: .work, minutes: 30)])
    let after = reviewSnapshot(
        sessions: [reviewSession(classification: .work, taskID: "private-task-id", minutes: 30)],
        totals: [.init(classification: .work, minutes: 30)]
    )

    let impact = try #require(DailyReviewCorrectionImpact(
        before: before,
        after: after,
        affectedSession: affected,
        requestedClassification: .work
    ))

    #expect(impact.classificationMove == nil)
    #expect(impact.taskAlignmentChange == .attached(minutes: 30))
    #expect(impact.taskAlignmentDetail == "Task alignment attached for 30 min.")
    #expect(!impact.accessibilitySummary.contains("private-task-id"))
}

@Test("task alignment removal reports only the persisted overlapping minutes")
func correctionImpactReportsRemovedTaskAlignment() throws {
    let affected = reviewSession(classification: .work, taskID: "private-task-id", minutes: 45)
    let before = reviewSnapshot(sessions: [affected], totals: [.init(classification: .work, minutes: 45)])
    let after = reviewSnapshot(
        sessions: [reviewSession(classification: .work, minutes: 45)],
        totals: [.init(classification: .work, minutes: 45)]
    )

    let impact = try #require(DailyReviewCorrectionImpact(
        before: before,
        after: after,
        affectedSession: affected,
        requestedClassification: .work
    ))

    #expect(impact.taskAlignmentChange == .removed(minutes: 45))
    #expect(impact.taskAlignmentDetail == "Task alignment removed from 45 min.")
}

@Test("review statement impact compares the actual before and after statement")
func correctionImpactReportsChangedReviewStatement() throws {
    let affected = reviewSession(classification: .work, minutes: 15)
    let totals = [DailyReviewTotal(classification: .work, minutes: 15)]
    let before = reviewSnapshot(
        sessions: [affected],
        totals: totals,
        hypothesis: "Work was the largest covered category."
    )
    let after = reviewSnapshot(
        sessions: [affected],
        totals: totals,
        hypothesis: "Coverage was too limited for a review statement."
    )

    let impact = try #require(DailyReviewCorrectionImpact(
        before: before,
        after: after,
        affectedSession: affected,
        requestedClassification: .work
    ))

    #expect(impact.classificationMove == nil)
    #expect(impact.taskAlignmentChange == .unchanged(minutes: 0))
    #expect(impact.reviewStatementChange == .changed)
    #expect(impact.reviewStatementDetail == "The review statement changed after recalculation.")
    #expect(!impact.accessibilitySummary.contains("Coverage was too limited"))
}

@Test("combined correction impact exposes every actual result without private identifiers")
func correctionImpactCombinesAllDimensions() throws {
    let affected = reviewSession(application: "Private Client Portal", classification: .gaming, minutes: 25)
    let before = reviewSnapshot(
        sessions: [affected],
        totals: [.init(classification: .gaming, minutes: 25)],
        hypothesis: "Gaming was the largest covered category."
    )
    let after = reviewSnapshot(
        sessions: [reviewSession(application: "Private Client Portal", classification: .work, taskID: "secret-42", minutes: 25)],
        totals: [.init(classification: .work, minutes: 25)],
        hypothesis: "Work was the largest covered category."
    )

    let impact = try #require(DailyReviewCorrectionImpact(
        before: before,
        after: after,
        affectedSession: affected,
        requestedClassification: .work
    ))

    #expect(impact.classificationMove == .init(from: .gaming, to: .work, minutes: 25))
    #expect(impact.taskAlignmentChange == .attached(minutes: 25))
    #expect(impact.reviewStatementChange == .changed)
    #expect(impact.accessibilitySummary == "Moved 25 min from Gaming to Work. Task alignment attached for 25 min. The review statement changed after recalculation.")
    #expect(!impact.accessibilitySummary.contains("Private Client Portal"))
    #expect(!impact.accessibilitySummary.contains("secret-42"))
}

@Test("no persisted classification alignment or statement change suppresses the impact card")
func correctionImpactSuppressesNoOp() {
    let affected = reviewSession(classification: .work, taskID: "task-1", minutes: 30)
    let snapshot = reviewSnapshot(
        sessions: [affected],
        totals: [.init(classification: .work, minutes: 30)],
        hypothesis: "Work was the largest covered category."
    )

    #expect(DailyReviewCorrectionImpact(
        before: snapshot,
        after: snapshot,
        affectedSession: affected,
        requestedClassification: .work
    ) == nil)
}

@MainActor
@Test("controller publishes impact from the reloaded persisted snapshot and clears it on a normal reload")
func correctionControllerUsesReloadedSnapshots() throws {
    let affected = reviewSession(classification: .gaming, minutes: 25)
    let before = reviewSnapshot(
        sessions: [affected],
        totals: [.init(classification: .gaming, minutes: 25)],
        hypothesis: "Gaming was the largest covered category."
    )
    let after = reviewSnapshot(
        sessions: [reviewSession(classification: .work, taskID: "secret-42", minutes: 25)],
        totals: [.init(classification: .work, minutes: 25)],
        hypothesis: "Work was the largest covered category."
    )
    let service = CorrectionImpactService(before: before, after: after)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let selectedDay = try #require(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
    let controller = DailyReviewController(
        service: service,
        selectedDay: selectedDay,
        calendar: calendar
    )

    controller.load()
    #expect(controller.correctionImpact == nil)
    #expect(controller.correct(
        session: affected,
        classification: .work,
        taskID: "secret-42",
        splitAtMidpoint: false,
        applyToFuture: false
    ))
    #expect(controller.correctionImpact?.classificationMove?.minutes == 25)
    #expect(controller.correctionImpact?.taskAlignmentChange == .attached(minutes: 25))
    #expect(controller.correctionImpact?.reviewStatementChange == .changed)

    controller.load()
    #expect(controller.correctionImpact == nil)
}

private func reviewSession(
    application: String = "Editor",
    classification: BehaviorClassification,
    taskID: String? = nil,
    minutes: Int
) -> DailyReviewSession {
    let start = Date(timeIntervalSince1970: 1_783_663_200)
    return DailyReviewSession(
        sourceDay: "2026-07-10",
        start: start,
        end: start.addingTimeInterval(TimeInterval(minutes * 60)),
        application: application,
        classification: classification,
        taskID: taskID,
        observationCount: minutes
    )
}

private func reviewSnapshot(
    sessions: [DailyReviewSession],
    totals: [DailyReviewTotal],
    hypothesis: String? = nil
) -> DailyReviewSnapshot {
    DailyReviewSnapshot(
        sourceDay: "2026-07-10",
        sessions: sessions,
        totals: totals,
        hypothesis: hypothesis,
        hypothesisState: .pending,
        confirmedAt: nil
    )
}

private final class CorrectionImpactService: DailyReviewServicing {
    private let before: DailyReviewSnapshot
    private let after: DailyReviewSnapshot
    private var correctionWasSaved = false

    init(before: DailyReviewSnapshot, after: DailyReviewSnapshot) {
        self.before = before
        self.after = after
    }

    func load(sourceDay: String) throws -> DailyReviewSnapshot {
        correctionWasSaved ? after : before
    }

    func mostRecentUnfinishedReview() throws -> UnfinishedDailyReview? { nil }

    func correct(
        _ session: DailyReviewSession,
        to classification: BehaviorClassification,
        taskID: String?,
        from splitDate: Date?,
        applyToFuture: Bool
    ) throws {
        correctionWasSaved = true
    }

    func classificationRules() throws -> [AppClassificationCorrectionRule] { [] }
    func merge(_ left: DailyReviewSession, with right: DailyReviewSession) throws { throw CorrectionImpactTestError.unused }
    func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func savePersonalNote(_ note: String?, sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func confirm(sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func skip(sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func deferReview(sourceDay: String, until date: Date) throws { throw CorrectionImpactTestError.unused }
    func resumeDeferredReview(sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func saveOfflineWork(id: String?, sourceDay: String, taskID: String?, startedAt: Date, durationMinutes: Int, note: String?) throws -> String { throw CorrectionImpactTestError.unused }
    func deleteOfflineWork(id: String, sourceDay: String) throws { throw CorrectionImpactTestError.unused }
    func upsertClassificationRule(for session: DailyReviewSession, classification: BehaviorClassification) throws -> AppClassificationCorrectionRule { throw CorrectionImpactTestError.unused }
    func removeClassificationRule(normalizedApplication: String) throws { throw CorrectionImpactTestError.unused }
    func resetClassificationRules() throws -> Int { throw CorrectionImpactTestError.unused }
}

private enum CorrectionImpactTestError: Error {
    case unused
}
