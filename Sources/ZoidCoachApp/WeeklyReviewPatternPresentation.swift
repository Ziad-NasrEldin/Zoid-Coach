import Foundation
import ZoidCoachCore

struct WeeklyReviewPatternPresentation: Equatable, Sendable {
    let hypothesis: String
    let confidenceLabel: String
    let sampleLabel: String
    let evidenceHeading: String
    let evidenceLines: [String]
    let alternativeExplanation: String
    let causalityCaveat: String
    let learningStatusLabel: String
    let learningSourceLabel: String
    let learningBoundaryDetail: String
    let collapsedAccessibilitySummary: String
    let expandedAccessibilitySummary: String
    let hasSufficientEvidence: Bool

    init(
        pattern: WeeklyReviewPattern,
        learningBoundary: HypothesisLearningBoundary? = nil
    ) {
        let evidenceLines = pattern.examples.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasSufficientEvidence = pattern.sampleCount > 0 && !evidenceLines.isEmpty
        let sampleLabel = pattern.sampleCount == 1
            ? "1 OBSERVED SAMPLE"
            : "\(pattern.sampleCount) OBSERVED SAMPLES"
        let evidenceHeading = hasSufficientEvidence
            ? "OBSERVED EVIDENCE"
            : "INSUFFICIENT EVIDENCE"
        let accessibleEvidenceHeading = hasSufficientEvidence
            ? "Observed evidence"
            : "Insufficient evidence"
        let visibleEvidence = hasSufficientEvidence
            ? evidenceLines
            : ["No observed examples support this hypothesis yet."]
        let confidenceLabel = hasSufficientEvidence
            ? "\(pattern.confidencePercent)% CONFIDENCE"
            : "INSUFFICIENT EVIDENCE"
        let causalityCaveat = hasSufficientEvidence
            ? "NOT PROVEN CAUSE · These observations can support a hypothesis, but they do not prove why it happened."
            : "NOT PROVEN CAUSE · Keep this as a question until observed evidence is available."
        let learningStatusLabel = learningBoundary?.statusLabel ?? "NOT LEARNED"
        let learningSourceLabel = "SOURCE DAYS \(pattern.dateRange.startDay) TO \(pattern.dateRange.endDay) · \(sampleLabel)"
        let learningBoundaryDetail = learningBoundary?.detail
            ?? "This weekly pattern remains a hypothesis and is not a learned fact. It can only be promoted after you explicitly accept the corresponding review hypothesis."

        self.hypothesis = pattern.conclusion
        self.confidenceLabel = confidenceLabel
        self.sampleLabel = sampleLabel
        self.evidenceHeading = evidenceHeading
        self.evidenceLines = visibleEvidence
        self.alternativeExplanation = pattern.alternativeExplanation
        self.causalityCaveat = causalityCaveat
        self.learningStatusLabel = learningStatusLabel
        self.learningSourceLabel = learningSourceLabel
        self.learningBoundaryDetail = learningBoundaryDetail
        self.hasSufficientEvidence = hasSufficientEvidence
        collapsedAccessibilitySummary = [
            "Hypothesis: \(pattern.conclusion)",
            "\(sampleLabel). \(confidenceLabel).",
            "Learning status: \(learningStatusLabel). \(learningSourceLabel).",
            learningBoundaryDetail,
            causalityCaveat,
        ].joined(separator: " ")
        expandedAccessibilitySummary = [
            "Hypothesis: \(pattern.conclusion)",
            "\(sampleLabel). \(confidenceLabel).",
            "Learning status: \(learningStatusLabel). \(learningSourceLabel).",
            learningBoundaryDetail,
            "\(accessibleEvidenceHeading): \(visibleEvidence.joined(separator: "; "))",
            "Alternative explanation: \(pattern.alternativeExplanation)",
            causalityCaveat,
        ].joined(separator: " ")
    }

    func accessibilitySummary(showsEvidence: Bool) -> String {
        showsEvidence ? expandedAccessibilitySummary : collapsedAccessibilitySummary
    }
}

extension WeeklyReviewPattern {
    var learningCandidate: ReviewHypothesisLearningCandidate {
        ReviewHypothesisLearningCandidate(
            id: "weekly-review:\(dateRange.startDay):\(dateRange.endDay):\(id)",
            hypothesis: conclusion,
            sourceDay: "\(dateRange.startDay) TO \(dateRange.endDay)",
            evidence: examples
        )
    }
}
