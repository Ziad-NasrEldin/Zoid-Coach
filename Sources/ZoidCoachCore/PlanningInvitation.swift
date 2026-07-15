import Foundation

public enum PlanningDayMode: String, Codable, Equatable, Sendable {
    case invitation
    case snoozed
    case dismissed
    case planning
    case unplanned
}

public struct PlanningDayStatus: Codable, Equatable, Sendable {
    public let mode: PlanningDayMode
    public let resumesAt: Date?
    public let driftInterventionsAllowed: Bool

    public init(
        mode: PlanningDayMode,
        resumesAt: Date? = nil,
        driftInterventionsAllowed: Bool = false
    ) {
        self.mode = mode
        self.resumesAt = resumesAt
        self.driftInterventionsAllowed = driftInterventionsAllowed
    }
}

public enum PlanningInvitationPolicy {
    public static let snoozeDuration: TimeInterval = 15 * 60
    public static let temporaryDismissDuration: TimeInterval = 2 * 60 * 60

    public static func promptDraft(
        localDay: String,
        itemCount: Int,
        expiresAt: Date?,
        decisionKey: String? = nil,
        notBefore: Date? = nil,
        followUpKind: PlanningDayMode? = nil
    ) -> PromptDraft {
        var payload = [
            "localDay": localDay,
            "itemCount": String(max(0, itemCount)),
            "allowsDismissal": "true"
        ]
        if let notBefore {
            payload["notBefore"] = ISO8601DateFormatter().string(from: notBefore)
        }
        if let followUpKind {
            payload["followUpKind"] = followUpKind.rawValue
        }
        return PromptDraft(
            decisionKey: decisionKey ?? "plan-ready:\(localDay)",
            type: "PLAN_READY",
            title: "Planning is available when you are ready",
            summary: itemCount > 0
                ? "You can review \(itemCount) suggested commitment\(itemCount == 1 ? "" : "s"), or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
                : "You can make a small plan, or start without one. You can snooze or dismiss this invitation for now. Nothing is blocked.",
            actions: actions,
            payload: payload,
            expiresAt: expiresAt
        )
    }

    public static let actions = [
        PromptAction(kind: .reviewPlan, title: "Review plan", role: .primary),
        PromptAction(kind: .acceptPlan, title: "Accept plan"),
        PromptAction(kind: .snoozePlanning, title: "Snooze 15 min"),
        PromptAction(kind: .workUnplanned, title: "Work unplanned"),
        PromptAction(kind: .dismissPlanning, title: "Dismiss for now")
    ]
}
