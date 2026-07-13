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
            ? " Coverage is limited and is labeled instead of filled with an AI guess."
            : " Coverage is sufficient for the displayed factual totals."
        return "Rules-only mode generated \(sessions) from local activity and task history. You can correct, reject, and confirm the record without configuring a model.\(coverage)"
    }
}
