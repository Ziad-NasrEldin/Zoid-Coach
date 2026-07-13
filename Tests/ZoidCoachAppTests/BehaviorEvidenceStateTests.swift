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
