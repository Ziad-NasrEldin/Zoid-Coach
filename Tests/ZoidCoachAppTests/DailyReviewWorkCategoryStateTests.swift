import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Daily review work categories")
struct DailyReviewWorkCategoryStateTests {
    @Test("corrected work is grouped conservatively and non-work is excluded")
    func conservativeBreakdown() {
        let state = DailyReviewWorkCategoryState(sessions: [
            session(application: "Xcode", classification: .work, start: 0, minutes: 12),
            session(application: "Zotero", classification: .work, start: 1_000, minutes: 7),
            session(application: "Safari", classification: .work, start: 2_000, minutes: 5),
            session(application: "Steam", classification: .gaming, start: 3_000, minutes: 20),
        ])

        #expect(state.categories.map(\.category) == WorkCategory.allCases)
        #expect(state.categories.map(\.minutes) == [12, 0, 7, 0, 0, 5])
        #expect(state.workMinutes == 24)
        #expect(state.uncategorizedMinutes == 5)
        #expect(state.detail.contains("5 work minutes remain Uncategorized"))
        #expect(state.categories.first?.accessibilityIdentifier == "reviews.work-category.deep_work")
        #expect(state.categories.last?.accessibilityLabel == "Uncategorized work, 5 minutes")
    }

    @Test("no-work and ambiguous-only states never invent a category")
    func honestNegativeStates() {
        let noWork = DailyReviewWorkCategoryState(sessions: [
            session(application: "Steam", classification: .gaming, start: 0, minutes: 10),
        ])
        #expect(!noWork.hasWork)
        #expect(noWork.categories.allSatisfy { $0.minutes == 0 })
        #expect(noWork.detail == "No corrected work sessions were observed for this review day. No category was invented.")

        let ambiguous = DailyReviewWorkCategoryState(sessions: [
            session(application: "Safari", classification: .work, start: 0, minutes: 10),
        ])
        #expect(ambiguous.hasWork)
        #expect(ambiguous.categories.first { $0.category == .uncategorized }?.minutes == 10)
        #expect(ambiguous.detail.contains("No category was guessed"))
    }

    @Test("mixed-application merged sessions stay uncategorized")
    func mergedSessionIsNotGuessed() {
        let merged = DailyReviewSession(
            sourceDay: "2026-07-14",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 15 * 60),
            application: "Xcode + Slack",
            applications: ["Xcode", "Slack"],
            classification: .work,
            observationCount: 2
        )

        let state = DailyReviewWorkCategoryState(sessions: [merged])
        #expect(state.categories.first { $0.category == .deepWork }?.minutes == 0)
        #expect(state.categories.first { $0.category == .communication }?.minutes == 0)
        #expect(state.categories.first { $0.category == .uncategorized }?.minutes == 15)
    }

    @Test("review ledger exposes stable container, detail, empty, and category identifiers")
    func accessibilityContracts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZoidCoachApp/Views/DailyReviewView.swift"),
            encoding: .utf8
        )
        let state = DailyReviewWorkCategoryState(sessions: [
            session(application: "Xcode", classification: .work, start: 0, minutes: 1),
        ])

        #expect(source.contains("reviews.work-categories"))
        #expect(source.contains("reviews.work-categories.detail"))
        #expect(source.contains("reviews.work-categories.empty"))
        #expect(state.categories.map(\.accessibilityIdentifier) == [
            "reviews.work-category.deep_work",
            "reviews.work-category.creative_work",
            "reviews.work-category.research",
            "reviews.work-category.communication",
            "reviews.work-category.administration",
            "reviews.work-category.uncategorized",
        ])
    }

    private func session(
        application: String,
        classification: BehaviorClassification,
        start: TimeInterval,
        minutes: Int
    ) -> DailyReviewSession {
        DailyReviewSession(
            sourceDay: "2026-07-14",
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + TimeInterval(minutes * 60)),
            application: application,
            classification: classification,
            observationCount: 1
        )
    }
}
