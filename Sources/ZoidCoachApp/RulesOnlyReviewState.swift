import Foundation
import ZoidCoachCore

struct RulesOnlyReviewState: Equatable, Sendable {
    let isRulesOnly: Bool
    let sessionCount: Int
    let hasLimitedCoverage: Bool

    var title: String { "LOCAL FACTS / NO AI REQUIRED" }

    var detail: String {
        guard isRulesOnly else {
            return "This review uses the current intelligence policy. Observed facts and corrections remain local either way."
        }
        let sessions = sessionCount == 1 ? "1 factual session" : "\(sessionCount) factual sessions"
        let coverage = hasLimitedCoverage
            ? " No observed sessions are available for this day; missing time remains unobserved instead of being filled with an AI guess."
            : " Displayed totals come only from those observed sessions; unobserved time is not inferred."
        return "Rules-only mode generated \(sessions) from local activity and task history. You can correct, reject, and confirm the record without configuring a model.\(coverage)"
    }
}
