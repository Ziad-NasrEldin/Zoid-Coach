import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Unplanned day review entry")
struct UnplannedDayReviewPresentationTests {
    @Test("explicit unplanned day without active work exposes the existing Review command")
    func unplannedDayExposesReviewCommand() throws {
        let presentation = try #require(UnplannedDayReviewPresentation(
            snapshot: snapshot(mode: .unplanned)
        ))

        #expect(presentation.action == .openDailyReview)
        #expect(presentation.isActionEnabled)
        #expect(presentation.buttonTitle == "END UNPLANNED DAY AND REVIEW")
        #expect(presentation.accessibilityLabel == "End the unplanned day and open today's review")
    }

    @Test("copy names factual inputs and refuses invented planned outcomes")
    func copyIsFactual() throws {
        let presentation = try #require(UnplannedDayReviewPresentation(
            snapshot: snapshot(mode: .unplanned)
        ))

        #expect(presentation.detail.contains("observed behavior"))
        #expect(presentation.detail.contains("tracked task outcomes"))
        #expect(presentation.detail.contains("without inventing planned commitments"))
        #expect(presentation.detail.contains("missed-plan conclusions"))
        #expect(presentation.accessibilityHint.contains("does not invent planned outcomes"))
    }

    @Test("planned and undecided states do not expose the unplanned-day command")
    func nonUnplannedStatesAreExcluded() {
        #expect(UnplannedDayReviewPresentation(snapshot: snapshot(mode: .planning)) == nil)
        #expect(UnplannedDayReviewPresentation(snapshot: snapshot(mode: .invitation)) == nil)
        #expect(UnplannedDayReviewPresentation(snapshot: snapshot(mode: .snoozed)) == nil)
        #expect(UnplannedDayReviewPresentation(snapshot: snapshot(mode: .dismissed)) == nil)
        #expect(UnplannedDayReviewPresentation(snapshot: nil) == nil)
    }

    @Test("active unplanned work keeps the timer-stopping end-workday command")
    func activeUnplannedStateIsExcluded() {
        #expect(UnplannedDayReviewPresentation(
            snapshot: snapshot(mode: .unplanned, hasActiveTask: true)
        ) == nil)
    }

    private func snapshot(
        mode: PlanningDayMode,
        hasActiveTask: Bool = false
    ) -> TodaySnapshot {
        let activeTask = hasActiveTask
            ? ActiveTaskSnapshot(taskID: "active", startedAt: Date(), elapsedMinutes: 3)
            : nil
        return TodaySnapshot(
            localDate: Date(timeIntervalSince1970: 1_800_000_000),
            timeZoneIdentifier: "Africa/Cairo",
            mainObjective: nil,
            taskRows: [],
            activeTask: activeTask,
            recommendation: NextTaskRecommendation(
                taskID: nil,
                sentence: "No plan is required for this review.",
                reasons: []
            ),
            behavior: BehaviorSummary(),
            coverage: TelemetryCoverage(
                isLimited: false,
                explanation: "Observed locally.",
                lastObservationAt: nil
            ),
            gaming: GamingStatus(
                budgetMinutes: 0,
                earnedMinutes: 0,
                usedMinutes: 0,
                unlockedRemainingMinutes: 0,
                lockedMinutes: 0,
                nextUnlockReason: "No unlock",
                confidenceIsLimited: false
            ),
            sourceFreshnessExplanation: "Ready",
            planningStatus: PlanningDayStatus(mode: mode)
        )
    }
}
