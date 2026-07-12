import Foundation
import ZoidCoachCore

public enum PlanningInvitationEffect: Equatable, Sendable {
    case none
    case snoozed(until: Date, promptID: String)
    case dismissed(until: Date, promptID: String)
    case unplanned
}

public final class PlanningInvitationService: @unchecked Sendable {
    private let store: PromptInboxStore
    private let now: @Sendable () -> Date
    private let formatter = ISO8601DateFormatter()

    public init(
        store: PromptInboxStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    public func apply(_ result: PromptResponseResult) throws -> PlanningInvitationEffect {
        guard result.episode.type == "PLAN_READY",
              let localDay = result.episode.payload["localDay"]
        else { return .none }
        switch result.response.action {
        case .snoozePlanning:
            let until = result.response.respondedAt.addingTimeInterval(PlanningInvitationPolicy.snoozeDuration)
            let followUp = try enqueueFollowUp(
                from: result.episode,
                localDay: localDay,
                until: until,
                mode: .snoozed
            )
            return .snoozed(until: until, promptID: followUp.id)
        case .dismissPlanning:
            let until = result.response.respondedAt.addingTimeInterval(PlanningInvitationPolicy.temporaryDismissDuration)
            let followUp = try enqueueFollowUp(
                from: result.episode,
                localDay: localDay,
                until: until,
                mode: .dismissed
            )
            return .dismissed(until: until, promptID: followUp.id)
        case .workUnplanned:
            return .unplanned
        default:
            return .none
        }
    }

    public func status(localDay: String, hasPlan: Bool, hasActiveUnplannedTask: Bool) throws -> PlanningDayStatus {
        guard let latest = try store.latestEpisode(decisionKeyPrefix: "plan-ready:\(localDay)") else {
            return hasPlan
                ? PlanningDayStatus(mode: .planning, driftInterventionsAllowed: false)
                : PlanningDayStatus(mode: .invitation)
        }
        if let raw = latest.payload["notBefore"],
           let resumesAt = formatter.date(from: raw), resumesAt > now(),
           let rawMode = latest.payload["followUpKind"],
           let mode = PlanningDayMode(rawValue: rawMode) {
            return PlanningDayStatus(mode: mode, resumesAt: resumesAt)
        }
        if latest.state.isUnresolved, latest.payload["followUpKind"] != nil {
            return PlanningDayStatus(mode: .invitation)
        }
        if hasPlan {
            return PlanningDayStatus(mode: .planning, driftInterventionsAllowed: false)
        }
        if let response = try store.responses(promptID: latest.id).last {
            switch response.action {
            case .workUnplanned:
                return PlanningDayStatus(
                    mode: .unplanned,
                    driftInterventionsAllowed: hasActiveUnplannedTask
                )
            case .reviewPlan:
                return PlanningDayStatus(mode: .planning)
            default:
                break
            }
        }
        return PlanningDayStatus(mode: .invitation)
    }

    @discardableResult
    public func beginUnplannedDay(
        localDay: String,
        itemCount: Int,
        expiresAt: Date?
    ) throws -> PromptResponseResult {
        let prefix = "plan-ready:\(localDay)"
        let existing = try store.latestEpisode(decisionKeyPrefix: prefix)
        let episode: PromptEpisode
        if let existing, existing.state.isUnresolved,
           existing.actions.contains(where: { $0.kind == .workUnplanned }) {
            episode = existing
        } else {
            episode = try store.enqueue(PlanningInvitationPolicy.promptDraft(
                localDay: localDay,
                itemCount: itemCount,
                expiresAt: expiresAt,
                decisionKey: "\(prefix):manual:\(Int(now().timeIntervalSince1970))"
            )).episode
        }
        let result = try store.respond(
            promptID: episode.id,
            action: .workUnplanned,
            actionToken: PromptResponseToken.make(promptID: episode.id, action: .workUnplanned),
            surface: .dashboard
        )
        try store.markEffectApplied(responseID: result.response.id)
        return result
    }

    public func dueFollowUps(at date: Date? = nil) throws -> [PromptEpisode] {
        try store.dueDeferredPlanningInvitations(at: date)
    }

    @discardableResult
    public func markPresented(_ promptID: String) throws -> PromptEpisode {
        try store.present(promptID: promptID)
    }

    @discardableResult
    public func dismiss(_ promptID: String) throws -> PromptEpisode {
        try store.dismiss(promptID: promptID)
    }

    private func enqueueFollowUp(
        from episode: PromptEpisode,
        localDay: String,
        until: Date,
        mode: PlanningDayMode
    ) throws -> PromptEpisode {
        let itemCount = Int(episode.payload["itemCount"] ?? "0") ?? 0
        let key = "plan-ready:\(localDay):\(mode.rawValue):\(Int(until.timeIntervalSince1970))"
        return try store.enqueue(PlanningInvitationPolicy.promptDraft(
            localDay: localDay,
            itemCount: itemCount,
            expiresAt: episode.expiresAt,
            decisionKey: key,
            notBefore: until,
            followUpKind: mode
        )).episode
    }
}
