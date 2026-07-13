import Foundation

struct SourceRepairGuidance: Equatable, Sendable {
    let impact: String?
    let actionHint: String
    let canAct: Bool

    init(source: SourceHealth) {
        canAct = source.state != .checking
        actionHint = Self.actionHint(for: source.id, actionTitle: source.actionTitle)
        guard source.state != .healthy else {
            impact = nil
            return
        }
        impact = Self.impact(for: source.id)
    }

    private static func impact(for source: SourceID) -> String {
        switch source {
        case .reminders:
            "Impact: Apple tasks and completion sync are unavailable. Local plans, estimates, sessions, and history remain usable."
        case .notifications:
            "Impact: Timely alerts may not appear. Every unresolved coaching choice remains available in Today."
        case .agent:
            "Impact: Background planning, refresh, and automatic actions may stop. Existing local data remains available in the app."
        case .calendar:
            "Impact: Conflict-aware placement and Calendar writes are unavailable. Capacity falls back to configured work windows."
        case .screenwatch:
            "Impact: Activity alignment and drift evidence may be incomplete. Manual task tracking and planning continue."
        }
    }

    private static func actionHint(for source: SourceID, actionTitle: String) -> String {
        switch source {
        case .reminders:
            "\(actionTitle) checks permission and refreshes Apple task access."
        case .notifications:
            "\(actionTitle) checks authorization and opens the repair path when needed."
        case .agent:
            "\(actionTitle) verifies the helper and exposes registration or Login Items repair."
        case .calendar:
            "\(actionTitle) checks permission and refreshes Calendar capacity."
        case .screenwatch:
            "\(actionTitle) checks the selected source and opens folder repair when needed."
        }
    }
}
