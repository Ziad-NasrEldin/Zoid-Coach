import Foundation
import ZoidCoachCore

struct BehaviorEvidenceCategory: Identifiable, Equatable, Sendable {
    let classification: BehaviorClassification
    let minutes: Int

    var id: BehaviorClassification { classification }

    var title: String {
        switch classification {
        case .work: "Work"
        case .gaming: "Gaming"
        case .distracting: "Distraction"
        case .idle: "Idle observed"
        case .unknown: "Unknown"
        }
    }

    var explanation: String {
        switch classification {
        case .work: "Activity classified as work by the current local rules."
        case .gaming: "Confidently observed gaming, shown separately from other distraction."
        case .distracting: "Non-gaming activity classified as distracting by the current local rules."
        case .idle: "Idle appears only when the local activity source observed a reliable idle state. Missing time is never silently counted as idle."
        case .unknown: "Zoid 666 did not have enough evidence to classify this time. Unknown is not distraction."
        }
    }
}

struct BehaviorEvidenceState: Equatable, Sendable {
    let categories: [BehaviorEvidenceCategory]
    let coverageTitle: String
    let coverageDetail: String
    let sourceIssueTitle: String?
    let sourceIssueDetail: String?

    init(snapshot: TodaySnapshot) {
        self.init(
            behavior: snapshot.behavior,
            coverage: snapshot.coverage,
            sources: snapshot.sources ?? [],
            sourceFreshnessExplanation: snapshot.sourceFreshnessExplanation
        )
    }

    init(
        behavior: BehaviorSummary,
        coverage: TelemetryCoverage,
        sources: [SourceFreshnessSnapshot],
        sourceFreshnessExplanation: String
    ) {
        categories = [
            BehaviorEvidenceCategory(classification: .work, minutes: behavior.workMinutes),
            BehaviorEvidenceCategory(classification: .gaming, minutes: behavior.gamingMinutes),
            BehaviorEvidenceCategory(classification: .distracting, minutes: behavior.distractingMinutes),
            BehaviorEvidenceCategory(classification: .idle, minutes: behavior.idleMinutes),
            BehaviorEvidenceCategory(classification: .unknown, minutes: behavior.unknownMinutes)
        ]
        coverageTitle = coverage.isLimited ? "LIMITED COVERAGE" : "CURRENT COVERAGE"
        coverageDetail = coverage.explanation.isEmpty
            ? sourceFreshnessExplanation
            : coverage.explanation

        let sourceIssue = sources.first {
            $0.sourceID.localizedCaseInsensitiveContains("screenwatch")
                && !Self.isHealthy($0.state)
        }
        sourceIssueTitle = sourceIssue.map { Self.sourceTitle($0.sourceID) }
        sourceIssueDetail = sourceIssue?.detail
    }

    var unknownMinutes: Int {
        categories.first { $0.classification == .unknown }?.minutes ?? 0
    }

    var hasSourceIssue: Bool {
        sourceIssueTitle != nil
    }

    private static func isHealthy(_ state: String) -> Bool {
        ["healthy", "current", "available", "connected"].contains(state.lowercased())
    }

    private static func sourceTitle(_ sourceID: String) -> String {
        sourceID
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
