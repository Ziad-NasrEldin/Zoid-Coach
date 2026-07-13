import Foundation
import ZoidCoachCore

struct RemoteEvidencePreview: Equatable {
    let heading: String
    let explanation: String
    let payload: String
    let excluded: [String]

    static func representative(for policy: RemoteEvidencePolicy) -> Self {
        switch policy {
        case .localOnly:
            Self(
                heading: "NO REMOTE PAYLOAD",
                explanation: "Rules-only and local planning keep this request on the Mac.",
                payload: "Nothing is sent.",
                excluded: commonExclusions
            )
        case .redactedMetadataOnly:
            Self(
                heading: "REPRESENTATIVE REDACTED PAYLOAD",
                explanation: "This is a fixed example, not your current data. Anonymous labels replace task and application names.",
                payload: """
                {
                  "task": "task_1",
                  "priority": "high",
                  "estimate_minutes": 45,
                  "due_offset_days": 0,
                  "available_focus_minutes": 120,
                  "recent_pattern": "2_carryovers"
                }
                """,
                excluded: commonExclusions + ["Task titles", "Application names"]
            )
        case .explicitPrivateContent:
            Self(
                heading: "REPRESENTATIVE PRIVATE-CONTENT PAYLOAD",
                explanation: "This is a fixed example, not your current data. A real request may include task and application names only after you save this explicit choice.",
                payload: """
                {
                  "task_title": "Prepare client proposal",
                  "application": "Writing app",
                  "priority": "high",
                  "estimate_minutes": 45,
                  "due_offset_days": 0,
                  "available_focus_minutes": 120
                }
                """,
                excluded: commonExclusions
            )
        }
    }

    private static let commonExclusions = [
        "Screenshots",
        "Extracted conversation text",
        "URLs",
        "Internal task identifiers",
        "Credentials",
    ]
}
