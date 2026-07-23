import Foundation
import ZoidCoachCore

struct DailyReviewEvidencePresentation: Equatable {
    enum Kind: String, CaseIterable, Hashable {
        case observedFacts = "observed-facts"
        case userContext = "user-context"
        case hypothesis
    }

    struct Section: Equatable {
        let kind: Kind
        let title: String
        let status: String
        let detail: String
    }

    let observedFacts: Section
    let userContext: Section
    let hypothesis: Section

    init(snapshot: DailyReviewSnapshot) {
        let sessionCount = snapshot.sessions.count
        let observedMinutes = snapshot.observedMinutes
        observedFacts = Section(
            kind: .observedFacts,
            title: "OBSERVED FACTS",
            status: sessionCount == 0
                ? "NO OBSERVED SESSIONS"
                : "\(sessionCount) OBSERVED SESSION\(sessionCount == 1 ? "" : "S") · \(observedMinutes) MIN",
            detail: "These values come from corrected local activity. Missing time stays unobserved instead of being filled in."
        )

        let hasPersonalContext = !(snapshot.personalNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        userContext = Section(
            kind: .userContext,
            title: "USER CONTEXT",
            status: hasPersonalContext ? "PERSONAL CONTEXT ADDED" : "NO PERSONAL CONTEXT",
            detail: "A personal note can explain circumstances, but it is never treated as observed behavior or learned automatically."
        )

        let hypothesisStatus: String
        if snapshot.hypothesis == nil {
            hypothesisStatus = "NO HYPOTHESIS"
        } else {
            hypothesisStatus = switch snapshot.hypothesisState {
            case .pending: "UNCONFIRMED HYPOTHESIS"
            case .accepted: "USER-ACCEPTED HYPOTHESIS"
            case .rejected: "REJECTED HYPOTHESIS"
            }
        }
        hypothesis = Section(
            kind: .hypothesis,
            title: "HYPOTHESIS",
            status: hypothesisStatus,
            detail: "A possible explanation is kept separate and remains a hypothesis, not an observed fact."
        )
    }

    var sections: [Section] {
        [observedFacts, userContext, hypothesis]
    }

    var accessibilitySummary: String {
        sections
            .map { section in
                let spokenTitle = switch section.kind {
                case .observedFacts: "Observed facts"
                case .userContext: "User context"
                case .hypothesis: "Hypothesis"
                }
                return "\(spokenTitle): \(section.status). \(section.detail)"
            }
            .joined(separator: " ")
    }
}
