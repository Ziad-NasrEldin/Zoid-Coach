import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Today behavior evidence")
struct BehaviorEvidenceStateTests {
    @Test("all five behavior totals stay separate and ordered")
    func fiveSeparateTotals() {
        let state = makeState(
            behavior: BehaviorSummary(
                workMinutes: 120,
                gamingMinutes: 25,
                distractingMinutes: 18,
                idleMinutes: 7,
                unknownMinutes: 13
            )
        )

        #expect(state.categories.map(\.classification) == [.work, .gaming, .distracting, .idle, .unknown])
        #expect(state.categories.map(\.minutes) == [120, 25, 18, 7, 13])
        #expect(state.unknownMinutes == 13)
        #expect(state.categories.first { $0.classification == .unknown }?.explanation.contains("not distraction") == true)
    }

    @Test("zero-minute categories remain visible instead of disappearing")
    func zeroCategoriesRemainVisible() {
        let state = makeState(behavior: BehaviorSummary(workMinutes: 45))

        #expect(state.categories.count == 5)
        #expect(state.categories.first { $0.classification == .gaming }?.minutes == 0)
        #expect(state.categories.first { $0.classification == .unknown }?.minutes == 0)
    }

    @Test("all named work categories and the honest uncategorized fallback stay visible")
    func workCategoriesStayVisibleAndAccessible() {
        let state = makeState(behavior: BehaviorSummary(
            workMinutes: 20,
            appUsage: [
                AppUsageBreakdown(application: "Xcode", observedSeconds: 600, percentage: 50, classification: .work),
                AppUsageBreakdown(application: "Safari", observedSeconds: 600, percentage: 50, classification: .work),
            ]
        ))

        #expect(state.workCategories.map(\.title) == [
            "Deep work",
            "Creative work",
            "Research",
            "Communication",
            "Administration",
            "Uncategorized work",
        ])
        #expect(state.workCategories.map(\.minutes) == [10, 0, 0, 0, 0, 10])
        #expect(state.workCategories[0].accessibilityLabel == "Deep work, 10 minutes")
        #expect(state.workCategories[5].accessibilityIdentifier == "today.behavior-evidence.work-category.uncategorized")
        #expect(state.workCategoryDetail.contains("10 minutes remain Uncategorized"))
    }

    @Test("work-category empty state does not invent a breakdown")
    func workCategoryEmptyStateIsTruthful() {
        let noWork = makeState(behavior: BehaviorSummary())
        #expect(noWork.workCategoryDetail == "No work-category time was observed today.")

        let missingAppEvidence = makeState(behavior: BehaviorSummary(workMinutes: 45))
        #expect(missingAppEvidence.workCategoryDetail.contains("does not identify a safe category"))
        #expect(missingAppEvidence.workCategories.allSatisfy { $0.minutes == 0 })
    }

    @Test("sub-minute evidence is floored without claiming that no safe category exists")
    func subMinuteEvidenceIsTruthful() {
        let recognized = makeState(behavior: BehaviorSummary(
            appUsage: [
                AppUsageBreakdown(application: "Xcode", observedSeconds: 59, percentage: 100, classification: .work),
            ]
        ))
        #expect(recognized.workCategories.first?.minutes == 0)
        #expect(recognized.workCategoryDetail.contains("below one complete observed minute"))
        #expect(recognized.workCategoryDetail.contains("never rounded up"))

        let mixed = makeState(behavior: BehaviorSummary(
            workMinutes: 10,
            appUsage: [
                AppUsageBreakdown(application: "Xcode", observedSeconds: 600, percentage: 94, classification: .work),
                AppUsageBreakdown(application: "Safari", observedSeconds: 59, percentage: 6, classification: .work),
            ]
        ))
        #expect(mixed.workCategories.map(\.minutes) == [10, 0, 0, 0, 0, 0])
        #expect(mixed.workCategoryDetail.contains("Less than one complete observed minute remains Uncategorized"))
    }

    @Test("limited coverage names the unhealthy source without calling missing time idle")
    func limitedCoverageNamesSource() {
        let state = makeState(
            behavior: BehaviorSummary(workMinutes: 30, idleMinutes: 4, unknownMinutes: 20),
            coverage: TelemetryCoverage(
                isLimited: true,
                explanation: "Limited coverage: the latest Screenwatch checkpoint is stale.",
                lastObservationAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            sources: [
                SourceFreshnessSnapshot(
                    sourceID: "screenwatch",
                    state: "stale",
                    detail: "No current observations are available.",
                    lastUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]
        )

        #expect(state.coverageTitle == "LIMITED COVERAGE")
        #expect(state.coverageDetail.contains("Screenwatch checkpoint is stale"))
        #expect(state.sourceIssueTitle == "Screenwatch")
        #expect(state.sourceIssueDetail == "No current observations are available.")
        #expect(state.categories.first { $0.classification == .idle }?.explanation.contains("Missing time is never silently counted as idle") == true)
    }

    @Test("healthy sources do not create a false repair warning")
    func healthySourceHasNoIssue() {
        let state = makeState(
            behavior: BehaviorSummary(workMinutes: 30),
            sources: [
                SourceFreshnessSnapshot(
                    sourceID: "screenwatch",
                    state: "healthy",
                    detail: "Current",
                    lastUpdatedAt: Date()
                )
            ]
        )

        #expect(state.coverageTitle == "CURRENT COVERAGE")
        #expect(!state.hasSourceIssue)
        #expect(state.sourceIssueDetail == nil)
    }

    @Test("an unrelated unhealthy source is not blamed for missing behavior totals")
    func unrelatedSourceIsNotBlamed() {
        let state = makeState(
            behavior: BehaviorSummary(workMinutes: 30, unknownMinutes: 10),
            coverage: TelemetryCoverage(
                isLimited: true,
                explanation: "Activity coverage is limited.",
                lastObservationAt: nil
            ),
            sources: [
                SourceFreshnessSnapshot(
                    sourceID: "reminders",
                    state: "unavailable",
                    detail: "Reminder access was denied.",
                    lastUpdatedAt: nil
                )
            ]
        )

        #expect(state.coverageTitle == "LIMITED COVERAGE")
        #expect(!state.hasSourceIssue)
        #expect(state.sourceIssueTitle == nil)
    }

    private func makeState(
        behavior: BehaviorSummary,
        coverage: TelemetryCoverage = TelemetryCoverage(
            isLimited: false,
            explanation: "Observed activity is current.",
            lastObservationAt: Date()
        ),
        sources: [SourceFreshnessSnapshot] = []
    ) -> BehaviorEvidenceState {
        BehaviorEvidenceState(
            behavior: behavior,
            coverage: coverage,
            sources: sources,
            sourceFreshnessExplanation: "Observed activity is current."
        )
    }
}
