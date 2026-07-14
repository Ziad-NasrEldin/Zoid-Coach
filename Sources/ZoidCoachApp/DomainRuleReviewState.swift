import Foundation
import ZoidCoachCore

struct DomainRuleReviewRow: Identifiable, Equatable, Sendable {
    let rule: ContextualDomainRule

    var id: String { rule.id }
    var pattern: String { rule.displayPattern }
    var outcome: String {
        switch rule.classification {
        case .work: "Work"
        case .gaming: "Gaming"
        case .distracting: "Distraction"
        case .idle: "Idle"
        case .unknown: "Unknown"
        }
    }
    var explanation: String { rule.explanation }
    var accessibilityIdentifier: String { "settings.domain-rules.rule.\(id)" }
    var accessibilityLabel: String { "\(pattern), \(outcome)" }
}

struct DomainRuleReviewState: Equatable, Sendable {
    let rows: [DomainRuleReviewRow]

    init(rules: [ContextualDomainRule] = ContextualClassificationRuleCatalog.domainRules) {
        rows = rules.map(DomainRuleReviewRow.init)
    }

    var summary: String {
        "\(rows.count) built-in domain and URL signals are active."
    }

    let privacyDetail = "Only built-in rule patterns are shown. Window titles, visited URLs, and browsing history never appear in this review."
}
