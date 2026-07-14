import Foundation
import ZoidCoachCore

public enum QANotificationReplacementProbeError: LocalizedError, Equatable, Sendable {
    case unavailable
    case invalidProbeID
    case originalRequired

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The notification replacement probe is available only in a signed QA package."
        case .invalidProbeID:
            "The notification replacement probe requires a short non-empty identifier."
        case .originalRequired:
            "Create the original QA notification before scheduling its replacement."
        }
    }
}

public enum QANotificationReplacementProbePhase: String, Codable, Equatable, Sendable {
    case original
    case replacement
}

public struct QANotificationReplacementProbeResult: Equatable, Sendable {
    public let phase: QANotificationReplacementProbePhase
    public let episode: PromptEpisode
    public let requestIdentifier: String
    public let scheduled: Bool

    public init(
        phase: QANotificationReplacementProbePhase,
        episode: PromptEpisode,
        requestIdentifier: String,
        scheduled: Bool
    ) {
        self.phase = phase
        self.episode = episode
        self.requestIdentifier = requestIdentifier
        self.scheduled = scheduled
    }
}

public struct QANotificationReplacementProbeSnapshot: Equatable, Sendable {
    public let latestPhase: QANotificationReplacementProbePhase?
    public let latestEpisode: PromptEpisode?
    public let latestResponse: PromptResponse?

    public init(
        latestPhase: QANotificationReplacementProbePhase?,
        latestEpisode: PromptEpisode?,
        latestResponse: PromptResponse?
    ) {
        self.latestPhase = latestPhase
        self.latestEpisode = latestEpisode
        self.latestResponse = latestResponse
    }
}

public actor QANotificationReplacementProbe {
    private static let decisionPrefix = "qa-notification-replacement:"
    private static let phasePayloadKey = "qaNotificationReplacementPhase"

    private let runtimeEnvironment: RuntimeEnvironment
    private let promptStore: PromptInboxStore
    private let notifications: PromptNotificationCoordinator
    private let probeID: String
    private let decisionKey: String
    private let now: @Sendable () -> Date

    public static func isAvailable(in runtimeEnvironment: RuntimeEnvironment) -> Bool {
        guard case .qa = runtimeEnvironment.mode else { return false }
        return runtimeEnvironment.packageMode == .qa
            && runtimeEnvironment.identity == RuntimeIdentity.qa
    }

    public init(
        runtimeEnvironment: RuntimeEnvironment,
        promptStore: PromptInboxStore,
        notifications: PromptNotificationCoordinator,
        probeID: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard Self.isAvailable(in: runtimeEnvironment) else {
            throw QANotificationReplacementProbeError.unavailable
        }
        let normalizedID = probeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, normalizedID.count <= 80 else {
            throw QANotificationReplacementProbeError.invalidProbeID
        }
        self.runtimeEnvironment = runtimeEnvironment
        self.promptStore = promptStore
        self.notifications = notifications
        self.probeID = normalizedID
        decisionKey = Self.decisionPrefix + normalizedID
        self.now = now
    }

    public func scheduleOriginal() async throws -> QANotificationReplacementProbeResult {
        if let current = try promptStore.latestEpisode(decisionKey: decisionKey),
           current.state.isUnresolved {
            _ = try promptStore.dismiss(promptID: current.id)
        }
        return try await schedule(
            phase: .original,
            title: "Original coaching update",
            summary: "Review the earlier plan before continuing.",
            primaryActionTitle: "Continue with earlier plan"
        )
    }

    public func scheduleReplacement() async throws -> QANotificationReplacementProbeResult {
        guard let original = try promptStore.latestEpisode(decisionKey: decisionKey),
              original.state.isUnresolved,
              Self.phase(of: original) == .original else {
            throw QANotificationReplacementProbeError.originalRequired
        }
        _ = try promptStore.dismiss(promptID: original.id)
        return try await schedule(
            phase: .replacement,
            title: "Updated coaching direction",
            summary: "The plan changed. Continue with the newest guidance.",
            primaryActionTitle: "Continue with updated plan"
        )
    }

    public func snapshot() throws -> QANotificationReplacementProbeSnapshot {
        let latest = try promptStore.latestEpisode(decisionKey: decisionKey)
        let response = try latest.flatMap { try promptStore.responses(promptID: $0.id).last }
        return QANotificationReplacementProbeSnapshot(
            latestPhase: latest.flatMap(Self.phase(of:)),
            latestEpisode: latest,
            latestResponse: response
        )
    }

    private func schedule(
        phase: QANotificationReplacementProbePhase,
        title: String,
        summary: String,
        primaryActionTitle: String
    ) async throws -> QANotificationReplacementProbeResult {
        let episode = try promptStore.enqueue(PromptDraft(
            decisionKey: decisionKey,
            type: PromptNotificationCategory.onboardingTest.rawValue,
            title: title,
            summary: summary,
            actions: [
                PromptAction(
                    kind: .continueIntentionally,
                    title: primaryActionTitle,
                    role: .primary
                ),
                PromptAction(kind: .ignore, title: "Use Today instead"),
            ],
            payload: [
                "allowsDismissal": "true",
                Self.phasePayloadKey: phase.rawValue,
                "qaNotificationReplacementProbeID": probeID,
            ],
            expiresAt: now().addingTimeInterval(60 * 60)
        )).episode
        let scheduled = (try? await notifications.schedule(episode)) == true
        return QANotificationReplacementProbeResult(
            phase: phase,
            episode: episode,
            requestIdentifier: PromptNotificationCoordinator.requestIdentifier(
                for: episode,
                notificationIdentity: runtimeEnvironment.identity.notification
            ),
            scheduled: scheduled
        )
    }

    private static func phase(of episode: PromptEpisode) -> QANotificationReplacementProbePhase? {
        episode.payload[phasePayloadKey].flatMap(QANotificationReplacementProbePhase.init(rawValue:))
    }
}
