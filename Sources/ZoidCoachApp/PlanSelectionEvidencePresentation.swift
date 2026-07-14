import Foundation

struct PlanSelectionEvidencePresentation: Equatable, Sendable {
    let heading: String
    let detail: String

    static func make(storedSelectionReason _: String?) -> Self {
        Self(
            heading: "EVIDENCE",
            detail: "Included in today's plan. Private ranking details are not displayed."
        )
    }
}
