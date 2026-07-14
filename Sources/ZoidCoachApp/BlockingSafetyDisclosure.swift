import Foundation

struct BlockingSafetyDisclosure: Equatable {
    struct Requirement: Equatable, Identifiable {
        enum ID: String, CaseIterable {
            case explicitEnablement = "explicit-enablement"
            case reversible
            case timeBounded = "time-bounded"
            case escapeHatch = "escape-hatch"
        }

        let id: ID
        let title: String
        let detail: String
    }

    struct Candidate: Equatable {
        let isExplicitlyEnabled: Bool
        let isReversible: Bool
        let maximumDurationMinutes: Int?
        let hasEscapeHatch: Bool
    }

    let statusTitle = "HARD BLOCKING OFF"
    let explanation = "Zoid 666 does not block applications or websites in this release. Coaching stays dismissible, and Pause remains available."
    let requirements: [Requirement] = [
        Requirement(
            id: .explicitEnablement,
            title: "Explicit enablement",
            detail: "A future blocking feature must stay off until you turn it on deliberately."
        ),
        Requirement(
            id: .reversible,
            title: "Reversible",
            detail: "You must be able to undo the block without losing plans, history, or policy choices."
        ),
        Requirement(
            id: .timeBounded,
            title: "Time-bounded",
            detail: "Every block must have a finite duration and end automatically."
        ),
        Requirement(
            id: .escapeHatch,
            title: "Escape hatch",
            detail: "A clear always-available action must end the block immediately."
        ),
    ]

    func unmetRequirements(for candidate: Candidate) -> [Requirement.ID] {
        requirements.compactMap { requirement in
            switch requirement.id {
            case .explicitEnablement:
                candidate.isExplicitlyEnabled ? nil : requirement.id
            case .reversible:
                candidate.isReversible ? nil : requirement.id
            case .timeBounded:
                candidate.maximumDurationMinutes.map { $0 > 0 } == true ? nil : requirement.id
            case .escapeHatch:
                candidate.hasEscapeHatch ? nil : requirement.id
            }
        }
    }

    var accessibilitySummary: String {
        ([statusTitle, explanation] + requirements.flatMap { [$0.title, $0.detail] })
            .joined(separator: ". ")
    }
}
