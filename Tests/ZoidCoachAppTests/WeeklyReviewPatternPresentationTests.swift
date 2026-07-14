import Testing
import ZoidCoachCore
@testable import ZoidCoachApp

@Test
func weeklyPatternPresentationSeparatesHypothesisEvidenceAndAlternative() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 4,
        examples: [
            "Monday: 42 focused minutes",
            "Wednesday: 38 focused minutes",
        ],
        confidencePercent: 72
    ))

    #expect(presentation.hypothesis == "Focused work was more consistent before noon.")
    #expect(presentation.confidenceLabel == "72% CONFIDENCE")
    #expect(presentation.sampleLabel == "4 OBSERVED SAMPLES")
    #expect(presentation.evidenceHeading == "OBSERVED EVIDENCE")
    #expect(presentation.evidenceLines.count == 2)
    #expect(presentation.alternativeExplanation == "Meeting load may have been lighter on those mornings.")
    #expect(presentation.causalityCaveat.contains("do not prove why"))
    #expect(presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternPresentationDoesNotPresentZeroSamplesAsCausal() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 0,
        examples: ["A leftover example must not make zero samples sufficient."],
        confidencePercent: 88
    ))

    #expect(presentation.confidenceLabel == "INSUFFICIENT EVIDENCE")
    #expect(presentation.sampleLabel == "0 OBSERVED SAMPLES")
    #expect(presentation.evidenceHeading == "INSUFFICIENT EVIDENCE")
    #expect(presentation.evidenceLines == ["No observed examples support this hypothesis yet."])
    #expect(presentation.causalityCaveat.contains("Keep this as a question"))
    #expect(!presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternPresentationDoesNotTreatMissingExamplesAsEvidence() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 3,
        examples: ["  ", ""],
        confidencePercent: 64
    ))

    #expect(presentation.confidenceLabel == "INSUFFICIENT EVIDENCE")
    #expect(presentation.evidenceHeading == "INSUFFICIENT EVIDENCE")
    #expect(!presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternAccessibilitySummaryNamesEveryEvidenceBoundary() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 1,
        examples: ["Tuesday: 31 focused minutes"],
        confidencePercent: 55
    ))

    #expect(presentation.accessibilitySummary.contains("Hypothesis:"))
    #expect(presentation.accessibilitySummary.contains("Observed evidence:"))
    #expect(presentation.accessibilitySummary.contains("Alternative explanation:"))
    #expect(presentation.accessibilitySummary.contains("NOT PROVEN CAUSE"))
}

private func pattern(
    sampleCount: Int,
    examples: [String],
    confidencePercent: Int
) -> WeeklyReviewPattern {
    WeeklyReviewPattern(
        id: "best-work-window",
        kind: .bestWorkWindow,
        title: "Morning focus",
        conclusion: "Focused work was more consistent before noon.",
        sampleCount: sampleCount,
        dateRange: WeeklyReviewDateRange(startDay: "2026-07-06", endDay: "2026-07-12"),
        examples: examples,
        confidencePercent: confidencePercent,
        alternativeExplanation: "Meeting load may have been lighter on those mornings."
    )
}
