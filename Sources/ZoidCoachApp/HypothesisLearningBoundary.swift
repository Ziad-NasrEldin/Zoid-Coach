import Foundation
import ZoidCoachCore

struct ReviewHypothesisLearningCandidate: Equatable, Sendable {
    let id: String
    let hypothesis: String
    let sourceDay: String
    let evidence: [String]

    init(id: String, hypothesis: String, sourceDay: String, evidence: [String]) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceDay = sourceDay.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evidence = evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum HypothesisLearningStatus: Equatable, Sendable {
    case notLearned
    case eligibleForPromotion
    case learned
}

struct HypothesisLearningBoundary: Equatable, Sendable {
    let candidate: ReviewHypothesisLearningCandidate
    let decision: DailyReviewHypothesisState
    let isPromoted: Bool

    var status: HypothesisLearningStatus {
        guard decision == .accepted else { return .notLearned }
        return isPromoted ? .learned : .eligibleForPromotion
    }

    var statusLabel: String {
        switch status {
        case .notLearned: "NOT LEARNED"
        case .eligibleForPromotion: "ACCEPTED · READY TO LEARN"
        case .learned: "LEARNED FROM EXPLICIT ACCEPTANCE"
        }
    }

    var detail: String {
        switch decision {
        case .pending:
            "This hypothesis is still awaiting your decision, so it cannot become a learned fact."
        case .rejected:
            "You rejected this hypothesis, so it cannot become a learned fact."
        case .accepted where isPromoted:
            "This hypothesis was explicitly accepted and promoted once with its source day and supporting evidence."
        case .accepted:
            "This hypothesis was explicitly accepted and is eligible for one idempotent promotion."
        }
    }

    var sourceLabel: String {
        let evidenceLabel = candidate.evidence.count == 1 ? "1 EVIDENCE ITEM" : "\(candidate.evidence.count) EVIDENCE ITEMS"
        return "SOURCE DAY \(candidate.sourceDay) · \(evidenceLabel)"
    }

    func accessibilitySummary(showsEvidence: Bool) -> String {
        var components = [
            "Learning status: \(statusLabel).",
            "Hypothesis: \(candidate.hypothesis)",
            "\(sourceLabel).",
            detail,
        ]
        if showsEvidence {
            let visibleEvidence = candidate.evidence.isEmpty
                ? "No supporting evidence is available."
                : candidate.evidence.joined(separator: "; ")
            components.append("Supporting evidence: \(visibleEvidence)")
        }
        return components.joined(separator: " ")
    }
}
