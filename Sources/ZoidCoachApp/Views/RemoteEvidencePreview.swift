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
                heading: "AUTOMATIC PLANNING / REDACTED EXAMPLE",
                explanation: "This fixed example mirrors the automatic planning request, not your current data. Anonymous labels replace task and application names.",
                payload: """
                {
                  "tasks": [{
                    "id": "task-1",
                    "title": "Task 1",
                    "dueDate": "2026-07-13T15:00:00Z",
                    "reminderPriority": 9,
                    "carryoverDays": 2,
                    "deferralCount": 1,
                    "recentAlignedMinutes": 30
                  }],
                  "recentBehavior": [{
                    "application": "Application 1",
                    "observationCount": 12
                  }]
                }
                """,
                excluded: commonExclusions + ["Task titles", "Application names"]
            )
        case .explicitPrivateContent:
            Self(
                heading: "AUTOMATIC PLANNING / PRIVATE-CONTENT EXAMPLE",
                explanation: "This fixed example mirrors the automatic planning request, not your current data. A real request may include task and application names only after you save this explicit choice.",
                payload: """
                {
                  "tasks": [{
                    "id": "task-1",
                    "title": "Prepare client proposal",
                    "dueDate": "2026-07-13T15:00:00Z",
                    "reminderPriority": 9,
                    "carryoverDays": 2,
                    "deferralCount": 1,
                    "recentAlignedMinutes": 30
                  }],
                  "recentBehavior": [{
                    "application": "Writing app",
                    "observationCount": 12
                  }]
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
