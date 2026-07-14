import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Contextual domain rule review")
struct ContextualDomainRuleReviewTests {
    @Test("reviewable domain rules stay ordered by classifier precedence")
    func stableRuleOrderAndOutcomes() {
        let rules = ContextualClassificationRuleCatalog.domainRules

        #expect(rules.map(\.displayPattern) == [
            "developer.*",
            "figma",
            "github",
            "stackoverflow",
            "battle.net",
            "playstation",
            "steam",
            "twitch",
            "xbox",
            "instagram",
            "reddit",
            "tiktok",
            "twitter",
            "x.com/home",
        ])
        #expect(rules.map(\.classification) == [
            .work, .work, .work, .work,
            .gaming, .gaming, .gaming, .gaming, .gaming,
            .distracting, .distracting, .distracting, .distracting, .distracting,
        ])
        #expect(Set(rules.map(\.id)).count == rules.count)
    }

    @Test("the reviewed catalog is the catalog used by contextual classification")
    func catalogDrivesClassificationWithoutChangingPrecedence() {
        let classifier = ContextualAppClassification()

        #expect(classifier.classify(
            application: "Safari",
            windowTitle: "Pull request",
            url: "https://github.com/zoid/review"
        ) == .work)
        #expect(classifier.classify(
            application: "Safari",
            windowTitle: "Live stream",
            url: "https://twitch.tv/example"
        ) == .gaming)
        #expect(classifier.classify(
            application: "Safari",
            windowTitle: "Home feed",
            url: "https://reddit.com/"
        ) == .distracting)
        #expect(classifier.classify(
            application: "Safari",
            windowTitle: "Client code review",
            url: "https://twitch.tv/example"
        ) == .work)
        #expect(classifier.classify(
            application: "Safari",
            windowTitle: "Unrecognized page",
            url: "https://example.invalid/"
        ) == .unknown)
    }

    @Test("review state is privacy safe and accessible without browsing evidence")
    func privacySafeAccessibleReviewRows() {
        let state = DomainRuleReviewState()

        #expect(state.rows.count == 14)
        #expect(state.summary == "14 built-in domain and URL signals are active.")
        #expect(state.privacyDetail == "Only built-in rule patterns are shown. Window titles, visited URLs, and browsing history never appear in this review.")
        #expect(state.rows.first?.accessibilityIdentifier == "settings.domain-rules.rule.work-developer")
        #expect(state.rows.first?.accessibilityLabel == "developer.*, Work")
        #expect(state.rows.last?.accessibilityLabel == "x.com/home, Distraction")
        #expect(state.rows.allSatisfy { !$0.accessibilityLabel.contains("https://") })
        #expect(state.rows.allSatisfy { !$0.explanation.isEmpty })
    }
}
