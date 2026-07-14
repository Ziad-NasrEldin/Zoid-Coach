import Testing
import ZoidCoachCore

@Suite("Work category evidence")
struct WorkCategoryTests {
    @Test("the five product categories stay visible in a stable order")
    func stableVisibleOrder() {
        let summary = BehaviorSummary()

        #expect(summary.workCategoryUsage.map(\.category) == [
            .deepWork,
            .creativeWork,
            .research,
            .communication,
            .administration,
            .uncategorized,
        ])
        #expect(summary.workCategoryUsage.allSatisfy { $0.observedSeconds == 0 })
    }

    @Test("only work-classified application evidence contributes to work categories")
    func aggregatesOnlyWorkEvidence() {
        let summary = BehaviorSummary(appUsage: [
            AppUsageBreakdown(application: "Xcode", observedSeconds: 900, percentage: 30, classification: .work),
            AppUsageBreakdown(application: "Cursor", observedSeconds: 300, percentage: 10, classification: .work),
            AppUsageBreakdown(application: "Figma", observedSeconds: 600, percentage: 20, classification: .work),
            AppUsageBreakdown(application: "Slack", observedSeconds: 180, percentage: 6, classification: .work),
            AppUsageBreakdown(application: "Reminders", observedSeconds: 120, percentage: 4, classification: .work),
            AppUsageBreakdown(application: "Steam", observedSeconds: 900, percentage: 30, classification: .gaming),
        ])

        #expect(summary.workCategoryUsage.map(\.observedSeconds) == [1_200, 600, 0, 180, 120, 0])
    }

    @Test("ambiguous work applications remain uncategorized instead of being guessed")
    func ambiguityRemainsVisible() {
        let summary = BehaviorSummary(appUsage: [
            AppUsageBreakdown(application: "Safari", observedSeconds: 420, percentage: 100, classification: .work),
        ])

        #expect(summary.workCategoryUsage.map(\.observedSeconds) == [0, 0, 0, 0, 0, 420])
    }

    @Test("research requires an explicitly recognized research application")
    func explicitResearchApplication() {
        let classifier = WorkCategoryClassifier()

        #expect(classifier.category(for: "Zotero") == .research)
        #expect(classifier.category(for: "Safari") == nil)
        #expect(classifier.category(for: "Unknown Research Browser") == nil)
    }

    @Test("partial minutes are not rounded up into time that was not observed")
    func partialMinutesDoNotOverstateEvidence() {
        let breakdown = WorkCategoryBreakdown(category: .deepWork, observedSeconds: 59)

        #expect(breakdown.observedMinutes == 0)
    }
}
