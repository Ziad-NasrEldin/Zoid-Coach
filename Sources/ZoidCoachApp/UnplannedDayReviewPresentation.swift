import ZoidCoachCore

struct UnplannedDayReviewPresentation: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case openDailyReview
    }

    let eyebrow = "UNPLANNED DAY"
    let title = "End and review this unplanned day"
    let detail = "Review observed behavior and tracked task outcomes without inventing planned commitments or missed-plan conclusions."
    let buttonTitle = "END UNPLANNED DAY AND REVIEW"
    let accessibilityLabel = "End the unplanned day and open today's review"
    let accessibilityHint = "The review uses observed behavior and tracked task outcomes. It does not invent planned outcomes."
    let isActionEnabled = true
    let action: Action = .openDailyReview

    init?(snapshot: TodaySnapshot?) {
        guard snapshot?.planningStatus?.mode == .unplanned,
              snapshot?.activeTask == nil
        else { return nil }
    }
}
