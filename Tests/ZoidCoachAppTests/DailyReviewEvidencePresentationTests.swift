import Foundation
import Testing
import ZoidCoachCore
@testable import ZoidCoachApp

@Test
func dailyReviewEvidencePresentationSeparatesFactsContextAndHypothesis() {
    let snapshot = evidenceSnapshot(
        sessions: [
            evidenceSession(application: "Xcode", start: 0, durationMinutes: 20, classification: .work),
            evidenceSession(application: "Steam", start: 1_800, durationMinutes: 15, classification: .gaming),
        ],
        totals: [
            DailyReviewTotal(classification: .work, minutes: 20),
            DailyReviewTotal(classification: .gaming, minutes: 15),
        ],
        hypothesis: "Late gaming may have followed an unfinished task.",
        hypothesisState: .pending,
        personalNote: "The task was waiting on a teammate."
    )

    let presentation = DailyReviewEvidencePresentation(snapshot: snapshot)

    #expect(presentation.sections.map(\.kind) == [.observedFacts, .userContext, .hypothesis])
    #expect(presentation.observedFacts.status == "2 OBSERVED SESSIONS · 35 MIN")
    #expect(presentation.observedFacts.detail.contains("corrected local activity"))
    #expect(presentation.observedFacts.detail.contains("Missing time stays unobserved"))
    #expect(presentation.userContext.status == "PERSONAL CONTEXT ADDED")
    #expect(presentation.userContext.detail.contains("never treated as observed behavior"))
    #expect(presentation.hypothesis.status == "UNCONFIRMED HYPOTHESIS")
    #expect(presentation.hypothesis.detail.contains("not an observed fact"))
}

@Test
func dailyReviewEvidencePresentationKeepsEmptyStatesExplicit() {
    let presentation = DailyReviewEvidencePresentation(snapshot: evidenceSnapshot())

    #expect(presentation.observedFacts.status == "NO OBSERVED SESSIONS")
    #expect(presentation.userContext.status == "NO PERSONAL CONTEXT")
    #expect(presentation.hypothesis.status == "NO HYPOTHESIS")
    #expect(presentation.accessibilitySummary.contains("Observed facts: NO OBSERVED SESSIONS"))
    #expect(presentation.accessibilitySummary.contains("User context: NO PERSONAL CONTEXT"))
    #expect(presentation.accessibilitySummary.contains("Hypothesis: NO HYPOTHESIS"))
}

@Test
func acceptedOrRejectedHypothesisIsNeverRelabeledAsFact() {
    let accepted = DailyReviewEvidencePresentation(snapshot: evidenceSnapshot(
        hypothesis: "A possible explanation.",
        hypothesisState: .accepted
    ))
    let rejected = DailyReviewEvidencePresentation(snapshot: evidenceSnapshot(
        hypothesis: "A possible explanation.",
        hypothesisState: .rejected
    ))

    #expect(accepted.hypothesis.status == "USER-ACCEPTED HYPOTHESIS")
    #expect(rejected.hypothesis.status == "REJECTED HYPOTHESIS")
    #expect(accepted.hypothesis.detail.contains("not an observed fact"))
    #expect(rejected.hypothesis.detail.contains("not an observed fact"))
}

private func evidenceSnapshot(
    sessions: [DailyReviewSession] = [],
    totals: [DailyReviewTotal] = [],
    hypothesis: String? = nil,
    hypothesisState: DailyReviewHypothesisState = .pending,
    personalNote: String? = nil
) -> DailyReviewSnapshot {
    DailyReviewSnapshot(
        sourceDay: "2026-07-14",
        sessions: sessions,
        totals: totals,
        hypothesis: hypothesis,
        hypothesisState: hypothesisState,
        confirmedAt: nil,
        personalNote: personalNote
    )
}

private func evidenceSession(
    application: String,
    start: TimeInterval,
    durationMinutes: Int,
    classification: BehaviorClassification
) -> DailyReviewSession {
    let startedAt = Date(timeIntervalSince1970: start)
    return DailyReviewSession(
        sourceDay: "2026-07-14",
        start: startedAt,
        end: startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60)),
        application: application,
        classification: classification,
        observationCount: 1
    )
}
