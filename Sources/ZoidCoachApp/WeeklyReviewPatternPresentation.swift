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
    let accessibilitySummary: String
    let hasSufficientEvidence: Bool

    init(pattern: WeeklyReviewPattern) {
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

        self.hypothesis = pattern.conclusion
        self.confidenceLabel = confidenceLabel
        self.sampleLabel = sampleLabel
        self.evidenceHeading = evidenceHeading
        self.evidenceLines = visibleEvidence
        self.alternativeExplanation = pattern.alternativeExplanation
        self.causalityCaveat = causalityCaveat
        self.hasSufficientEvidence = hasSufficientEvidence
        accessibilitySummary = [
            "Hypothesis: \(pattern.conclusion)",
            "\(sampleLabel). \(confidenceLabel).",
            "\(accessibleEvidenceHeading): \(visibleEvidence.joined(separator: "; "))",
            "Alternative explanation: \(pattern.alternativeExplanation)",
            causalityCaveat,
        ].joined(separator: " ")
    }
}
