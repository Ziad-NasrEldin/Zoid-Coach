import Foundation
import ZoidCoachCore

struct DailyReviewEvidenceLayer: Identifiable, Equatable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case facts
        case context
        case hypothesis
    }

    let kind: Kind
    let title: String
    let body: String
    let detail: String

    var id: Kind { kind }
    var accessibilityIdentifier: String { "reviews.evidence-layers.\(kind.rawValue)" }
    var accessibilityLabel: String { "\(title). \(body). \(detail)" }
}

struct DailyReviewEvidenceLayersState: Equatable, Sendable {
    let layers: [DailyReviewEvidenceLayer]

    init(snapshot: DailyReviewSnapshot) {
        let sessionCount = snapshot.sessions.count
        let completedCount = snapshot.completedTasks.count
        let unknownMinutes = snapshot.totals.first { $0.classification == .unknown }?.minutes ?? 0

        let factsBody: String
        if snapshot.actualMinutes == 0, completedCount == 0 {
            factsBody = "No covered activity or completed task was recorded for this day."
        } else {
            factsBody = "\(snapshot.observedMinutes) corrected observed minute\(snapshot.observedMinutes == 1 ? "" : "s") across \(sessionCount) session\(sessionCount == 1 ? "" : "s"), plus \(snapshot.offlineMinutes) minute\(snapshot.offlineMinutes == 1 ? "" : "s") recorded away from the Mac and \(completedCount) completed task\(completedCount == 1 ? "" : "s")."
        }

        var contextParts: [String] = []
        if snapshot.observedMinutes == 0 {
            contextParts.append("Screenwatch contributed no corrected minutes")
        }
        if unknownMinutes > 0 {
            contextParts.append("\(unknownMinutes) observed minute\(unknownMinutes == 1 ? " remains" : "s remain") Unknown")
        }
        if snapshot.offlineMinutes > 0 {
            contextParts.append("away-from-Mac time is self-recorded and kept separate")
        }
        if snapshot.personalNote != nil {
            contextParts.append("a personal note supplies user context but is not treated as observation")
        }
        if contextParts.isEmpty {
            contextParts.append("no Unknown time, away-from-Mac entry, or personal-note context is recorded in this review snapshot")
        }
        let contextBody = contextParts.joined(separator: "; ") + "."

        let hypothesisBody = snapshot.hypothesis
            ?? "No possible explanation was generated because the covered evidence is insufficient."

        layers = [
            DailyReviewEvidenceLayer(
                kind: .facts,
                title: "OBSERVED FACTS",
                body: factsBody,
                detail: "These values come from corrected local evidence and task records."
            ),
            DailyReviewEvidenceLayer(
                kind: .context,
                title: "CONTEXT AND LIMITS",
                body: contextBody,
                detail: "Context can qualify interpretation, but it never rewrites an observed fact."
            ),
            DailyReviewEvidenceLayer(
                kind: .hypothesis,
                title: "POSSIBLE HYPOTHESIS",
                body: hypothesisBody,
                detail: "A hypothesis is optional, uncertain, and never presented as fact."
            ),
        ]
    }
}
