import CryptoKit
import Foundation

public enum PromptEpisodeState: String, Codable, CaseIterable, Sendable {
    case detected
    case queued
    case presented
    case responded
    case timedOut = "timed_out"
    case dismissed

    public var isUnresolved: Bool {
        switch self {
        case .detected, .queued, .presented: true
        case .responded, .timedOut, .dismissed: false
        }
    }
}

public enum PromptResolutionOrigin: String, Codable, Sendable {
    case user
    case system
}

public enum PromptResolutionReason: String, Codable, Sendable {
    case explicitDismissal = "explicit_dismissal"
    case screenwatchEvidenceInvalid = "screenwatch_evidence_invalid"
}

public enum PromptEpisodeEvent: Equatable, Sendable {
    case queue
    case present
    case respond
    case dismiss
    case expire
}

public enum PromptStateMachineError: Error, Equatable, Sendable {
    case invalidTransition(from: PromptEpisodeState, event: PromptEpisodeEvent)
}

public struct PromptEpisodeStateMachine: Sendable {
    public init() {}

    public func transition(from state: PromptEpisodeState, on event: PromptEpisodeEvent) throws -> PromptEpisodeState {
        switch (state, event) {
        case (.detected, .queue): .queued
        case (.queued, .present): .presented
        case (.presented, .respond): .responded
        case (.detected, .dismiss), (.queued, .dismiss), (.presented, .dismiss): .dismissed
        case (.detected, .expire), (.queued, .expire), (.presented, .expire): .timedOut
        default: throw PromptStateMachineError.invalidTransition(from: state, event: event)
        }
    }
}

public enum PromptActionKind: String, Codable, CaseIterable, Sendable {
    case startRecommendedTask = "start_recommended_task"
    case startShortSprint = "start_short_sprint"
    case startWorkSprint = "start_work_sprint"
    case returnToActiveTask = "return_to_active_task"
    case fiveMoreMinutes = "five_more_minutes"
    case startBreak = "start_break"
    case continueIntentionally = "continue_intentionally"
    case classifyAsSupportingWork = "classify_as_supporting_work"
    case classifyAsGaming = "classify_as_gaming"
    case keepActivityUnknown = "keep_activity_unknown"
    case pauseTask = "pause_task"
    case rescheduleTask = "reschedule_task"
    case markBlocked = "mark_blocked"
    case endWorkday = "end_workday"
    case ignore
    case acceptPlan = "accept_plan"
    case reviewPlan = "review_plan"
    case snoozePlanning = "snooze_planning"
    case dismissPlanning = "dismiss_planning"
    case workUnplanned = "work_unplanned"
    case undoPlanChange = "undo_plan_change"
    case addMeeting = "add_meeting"
    case editMeeting = "edit_meeting"
}

public enum PromptActionRole: String, Codable, Sendable {
    case primary
    case secondary
    case destructive
}

public struct PromptAction: Identifiable, Equatable, Codable, Sendable {
    public let kind: PromptActionKind
    public let title: String
    public let role: PromptActionRole
    public let requiresConfirmation: Bool

    public init(
        kind: PromptActionKind,
        title: String,
        role: PromptActionRole = .secondary,
        requiresConfirmation: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.role = role
        self.requiresConfirmation = requiresConfirmation
    }

    public var id: String { kind.rawValue }
}

public enum PromptSurface: String, Codable, Sendable {
    case dashboard
    case notification
    case loopback
}

public struct PromptEpisode: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let decisionKey: String
    public let type: String
    public let state: PromptEpisodeState
    public let title: String
    public let summary: String
    public let actions: [PromptAction]
    public let payload: [String: String]
    public let createdAt: Date
    public let expiresAt: Date?
    public let presentedAt: Date?
    public let resolvedAt: Date?
    public let resolutionOrigin: PromptResolutionOrigin?
    public let resolutionReason: PromptResolutionReason?

    public var allowsDismissal: Bool {
        payload["allowsDismissal"] == "true"
    }

    public var allowsDismissal: Bool {
        payload["allowsDismissal"] == "true"
    }

    public init(
        id: String,
        decisionKey: String,
        type: String,
        state: PromptEpisodeState = .detected,
        title: String,
        summary: String,
        actions: [PromptAction],
        payload: [String: String] = [:],
        createdAt: Date,
        expiresAt: Date? = nil,
        presentedAt: Date? = nil,
        resolvedAt: Date? = nil,
        resolutionOrigin: PromptResolutionOrigin? = nil,
        resolutionReason: PromptResolutionReason? = nil
    ) {
        self.id = id
        self.decisionKey = decisionKey
        self.type = type
        self.state = state
        self.title = title
        self.summary = summary
        self.actions = actions
        self.payload = payload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.presentedAt = presentedAt
        self.resolvedAt = resolvedAt
        self.resolutionOrigin = resolutionOrigin
        self.resolutionReason = resolutionReason
    }

    public func applying(_ event: PromptEpisodeEvent, at date: Date) throws -> PromptEpisode {
        let nextState = try PromptEpisodeStateMachine().transition(from: state, on: event)
        return PromptEpisode(
            id: id,
            decisionKey: decisionKey,
            type: type,
            state: nextState,
            title: title,
            summary: summary,
            actions: actions,
            payload: payload,
            createdAt: createdAt,
            expiresAt: expiresAt,
            presentedAt: event == .present ? date : presentedAt,
            resolvedAt: nextState.isUnresolved ? nil : date,
            resolutionOrigin: resolutionOrigin,
            resolutionReason: resolutionReason
        )
    }

    package func recordingResolution(
        origin: PromptResolutionOrigin,
        reason: PromptResolutionReason
    ) -> PromptEpisode {
        PromptEpisode(
            id: id,
            decisionKey: decisionKey,
            type: type,
            state: state,
            title: title,
            summary: summary,
            actions: actions,
            payload: payload,
            createdAt: createdAt,
            expiresAt: expiresAt,
            presentedAt: presentedAt,
            resolvedAt: resolvedAt,
            resolutionOrigin: origin,
            resolutionReason: reason
        )
    }
}

public struct PromptInboxTimelineEntry: Identifiable, Equatable, Codable, Sendable {
    public let episode: PromptEpisode
    public let response: PromptResponse?
    public let availableAt: Date?
    public let occurrence: Int

    public init(
        episode: PromptEpisode,
        response: PromptResponse? = nil,
        availableAt: Date? = nil,
        occurrence: Int = 1
    ) {
        self.episode = episode
        self.response = response
        self.availableAt = availableAt
        self.occurrence = max(1, occurrence)
    }

    public var id: String { episode.id }
    public var isReplay: Bool { occurrence > 1 }
}

public struct PromptInboxTimeline: Equatable, Codable, Sendable {
    public let awaitingResponse: [PromptInboxTimelineEntry]
    public let snoozed: [PromptInboxTimelineEntry]
    public let recent: [PromptInboxTimelineEntry]

    public init(
        awaitingResponse: [PromptInboxTimelineEntry] = [],
        snoozed: [PromptInboxTimelineEntry] = [],
        recent: [PromptInboxTimelineEntry] = []
    ) {
        self.awaitingResponse = awaitingResponse
        self.snoozed = snoozed
        self.recent = recent
    }

    public static let empty = PromptInboxTimeline()
    public var isEmpty: Bool { awaitingResponse.isEmpty && snoozed.isEmpty && recent.isEmpty }
}

public struct PromptInboxTimelineEntry: Identifiable, Equatable, Codable, Sendable {
    public let episode: PromptEpisode
    public let response: PromptResponse?
    public let availableAt: Date?
    public let occurrence: Int

    public init(
        episode: PromptEpisode,
        response: PromptResponse? = nil,
        availableAt: Date? = nil,
        occurrence: Int = 1
    ) {
        self.episode = episode
        self.response = response
        self.availableAt = availableAt
        self.occurrence = max(1, occurrence)
    }

    public var id: String { episode.id }
    public var isReplay: Bool { occurrence > 1 }
}

public struct PromptInboxTimeline: Equatable, Codable, Sendable {
    public let awaitingResponse: [PromptInboxTimelineEntry]
    public let snoozed: [PromptInboxTimelineEntry]
    public let recent: [PromptInboxTimelineEntry]

    public init(
        awaitingResponse: [PromptInboxTimelineEntry] = [],
        snoozed: [PromptInboxTimelineEntry] = [],
        recent: [PromptInboxTimelineEntry] = []
    ) {
        self.awaitingResponse = awaitingResponse
        self.snoozed = snoozed
        self.recent = recent
    }

    public static let empty = PromptInboxTimeline()
    public var isEmpty: Bool { awaitingResponse.isEmpty && snoozed.isEmpty && recent.isEmpty }
}

public struct PromptResponse: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let promptID: String
    public let action: PromptActionKind
    public let actionToken: String
    public let surface: PromptSurface
    public let respondedAt: Date

    public init(
        id: String,
        promptID: String,
        action: PromptActionKind,
        actionToken: String,
        surface: PromptSurface,
        respondedAt: Date
    ) {
        self.id = id
        self.promptID = promptID
        self.action = action
        self.actionToken = actionToken
        self.surface = surface
        self.respondedAt = respondedAt
    }
}

public enum PromptResponseToken {
    public static func make(promptID: String, action: PromptActionKind) -> String {
        let input = Data("zoid.prompt.response.v1\u{0}\(promptID)\u{0}\(action.rawValue)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    public static func episodeSeed(promptID: String) -> String {
        let input = Data("zoid.prompt.episode.v1\u{0}\(promptID)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

public struct PromptDraft: Equatable, Sendable {
    public let decisionKey: String
    public let type: String
    public let title: String
    public let summary: String
    public let actions: [PromptAction]
    public let payload: [String: String]
    public let expiresAt: Date?

    public init(
        decisionKey: String,
        type: String,
        title: String,
        summary: String,
        actions: [PromptAction],
        payload: [String: String] = [:],
        expiresAt: Date? = nil
    ) {
        self.decisionKey = decisionKey
        self.type = type
        self.title = title
        self.summary = summary
        self.actions = actions
        self.payload = payload
        self.expiresAt = expiresAt
    }
}

public enum BehaviorPromptPresentationIssue: String, Equatable, Sendable {
    case tooManySecondaryActions
    case unreliableElapsedEvidence
    case missingUncertaintyBoundary
    case coerciveLanguage
    case assertedIntent
}

public enum BehaviorPromptPresentationPolicy {
    public static let contractVersion = "1"
    public static let maximumSecondaryActions = 3

    public static func issues(for draft: PromptDraft) -> [BehaviorPromptPresentationIssue] {
        var issues: [BehaviorPromptPresentationIssue] = []
        guard draft.payload["behaviorPromptContractVersion"] == contractVersion else {
            return issues
        }
        if draft.actions.filter({ $0.role == .secondary }).count > maximumSecondaryActions {
            issues.append(.tooManySecondaryActions)
        }

        let copy = ([draft.title, draft.summary] + draft.actions.map(\.title))
            .joined(separator: " ")
            .lowercased()
        let coercivePhrases = [
            "you are lazy",
            "you failed",
            "you wasted",
            "disappointed in you",
            "bad choice",
            "lack discipline"
        ]
        if coercivePhrases.contains(where: copy.contains) {
            issues.append(.coerciveLanguage)
        }
        let assertedIntentPhrases = [
            "you wanted to",
            "you meant to",
            "you are avoiding",
            "you do not care",
            "you chose gaming over"
        ]
        if assertedIntentPhrases.contains(where: copy.contains) {
            issues.append(.assertedIntent)
        }
        if !copy.contains("not why") && !copy.contains("does not establish your intent") {
            issues.append(.missingUncertaintyBoundary)
        }

        guard let rawMinutes = draft.payload["observedGamingMinutes"],
              let minutes = Int(rawMinutes),
              let rawStart = draft.payload["evidenceStartedAtEpoch"],
              let startedAt = Int64(rawStart),
              let rawLatest = draft.payload["evidenceLatestAtEpoch"],
              let latestAt = Int64(rawLatest),
              latestAt >= startedAt,
              minutes == max(1, Int((latestAt - startedAt + 60) / 60)),
              draft.summary.localizedCaseInsensitiveContains("\(minutes) observed minutes")
        else {
            issues.append(.unreliableElapsedEvidence)
            return issues
        }
        return issues
    }
}

public struct PromptResponseCommand: Equatable, Codable, Sendable {
    public let promptID: String
    public let action: PromptActionKind
    public let actionToken: String
    public let surface: PromptSurface

    public init(promptID: String, action: PromptActionKind, actionToken: String, surface: PromptSurface) {
        self.promptID = promptID
        self.action = action
        self.actionToken = actionToken
        self.surface = surface
    }
}
