import Foundation
import ZoidCoachCore

public enum OnboardingTestPromptDelivery: String, Codable, Sendable {
    case notification
    case todayFallback = "today_fallback"
}

public struct OnboardingTestPromptResult: Equatable, Codable, Sendable {
    public let episode: PromptEpisode
    public let delivery: OnboardingTestPromptDelivery
    public let message: String

    public init(
        episode: PromptEpisode,
        delivery: OnboardingTestPromptDelivery,
        message: String
    ) {
        self.episode = episode
        self.delivery = delivery
        self.message = message
    }
}

public final class OnboardingTestPromptService: @unchecked Sendable {
    public static let promptType = "ONBOARDING_TEST"

    private let store: PromptInboxStore
    private let notifications: PromptNotificationCoordinator
    private let now: @Sendable () -> Date

    public init(
        store: PromptInboxStore,
        notifications: PromptNotificationCoordinator,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.notifications = notifications
        self.now = now
    }

    public func current(flowID: String) throws -> PromptEpisode? {
        try store.latestEpisode(decisionKey: decisionKey(flowID: flowID))
    }

    public func createOrDeliver(flowID: String) async throws -> OnboardingTestPromptResult {
        let episode: PromptEpisode
        if let existing = try current(flowID: flowID) {
            episode = existing
        } else {
            episode = try store.enqueue(PromptDraft(
                decisionKey: decisionKey(flowID: flowID),
                type: Self.promptType,
                title: "Choose where coaching should continue",
                summary: "This harmless setup prompt proves that every notification choice is also available in Today.",
                actions: [
                    PromptAction(
                        kind: .continueIntentionally,
                        title: "Continue setup",
                        role: .primary
                    ),
                    PromptAction(
                        kind: .ignore,
                        title: "Use Today instead"
                    ),
                ],
                payload: ["onboardingFlowID": flowID],
                expiresAt: now().addingTimeInterval(7 * 24 * 60 * 60)
            )).episode
        }
        guard episode.state.isUnresolved else {
            return OnboardingTestPromptResult(
                episode: episode,
                delivery: .todayFallback,
                message: "The setup prompt was already resolved and remains saved."
            )
        }
        let scheduled = (try? await notifications.schedule(episode)) == true
        return OnboardingTestPromptResult(
            episode: episode,
            delivery: scheduled ? .notification : .todayFallback,
            message: scheduled
                ? "The prompt was sent. Resolve it here or from the notification."
                : "Notifications are unavailable. The same prompt is ready here and in Today."
        )
    }

    private func decisionKey(flowID: String) -> String {
        "onboarding-test-prompt:\(flowID)"
    }
}
