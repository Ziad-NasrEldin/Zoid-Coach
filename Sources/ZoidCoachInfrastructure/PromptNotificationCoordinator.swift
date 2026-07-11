import Foundation
import UserNotifications
import ZoidCoachCore

public enum PromptNotificationCategory: String, CaseIterable, Sendable {
    case planReady = "PLAN_READY"
    case meetingCandidate = "MEETING_CANDIDATE"
    case planChanged = "PLAN_CHANGED"
    case wakeIntervention = "WAKE_INTERVENTION"

    public static func forPromptType(_ type: String) -> PromptNotificationCategory? {
        PromptNotificationCategory(rawValue: type)
    }
}

public final class PromptNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let promptStore: PromptInboxStore
    private let onResponse: @Sendable (PromptResponseResult) async -> Void

    public init(
        promptStore: PromptInboxStore,
        center: UNUserNotificationCenter = .current(),
        onResponse: @escaping @Sendable (PromptResponseResult) async -> Void = { _ in }
    ) {
        self.promptStore = promptStore
        self.center = center
        self.onResponse = onResponse
        super.init()
    }

    public func activate() {
        center.delegate = self
        center.setNotificationCategories(Self.categories())
    }

    @discardableResult
    public func schedule(_ episode: PromptEpisode, deliveryDate: Date? = nil) async throws -> Bool {
        guard let category = PromptNotificationCategory.forPromptType(episode.type) else { return false }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return false }
        let content = UNMutableNotificationContent()
        content.title = episode.title
        content.body = episode.summary
        content.categoryIdentifier = category.rawValue
        content.sound = .default
        content.userInfo = ["promptID": episode.id]
        let trigger: UNNotificationTrigger?
        if let deliveryDate, deliveryDate > Date() {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deliveryDate.timeIntervalSinceNow), repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(identifier: "zoid.prompt.\(episode.id)", content: content, trigger: trigger)
        try await center.add(request)
        return true
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let promptID = response.notification.request.content.userInfo["promptID"] as? String,
              let action = Self.actionKind(identifier: response.actionIdentifier)
        else {
            completionHandler()
            return
        }
        do {
            let result = try promptStore.respond(
                promptID: promptID,
                action: action,
                actionToken: PromptResponseToken.make(promptID: promptID, action: action),
                surface: .notification
            )
            completionHandler()
            Task { await onResponse(result) }
        } catch {
            completionHandler()
        }
    }

    public static func actionIdentifier(_ action: PromptActionKind) -> String {
        "ZOID_PROMPT_\(action.rawValue.uppercased())"
    }

    public static func actionKind(identifier: String) -> PromptActionKind? {
        guard identifier.hasPrefix("ZOID_PROMPT_") else { return nil }
        return PromptActionKind(rawValue: String(identifier.dropFirst("ZOID_PROMPT_".count)).lowercased())
    }

    private static func categories() -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: PromptNotificationCategory.planReady.rawValue,
                actions: [
                    action(.acceptPlan, title: "Accept"),
                    action(.reviewPlan, title: "Review", foreground: true)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PromptNotificationCategory.meetingCandidate.rawValue,
                actions: [
                    action(.addMeeting, title: "Add"),
                    action(.editMeeting, title: "Edit", foreground: true),
                    action(.ignore, title: "Ignore")
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PromptNotificationCategory.planChanged.rawValue,
                actions: [
                    action(.reviewPlan, title: "Review", foreground: true),
                    action(.undoPlanChange, title: "Undo")
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PromptNotificationCategory.wakeIntervention.rawValue,
                actions: [],
                intentIdentifiers: []
            )
        ]
    }

    private static func action(_ kind: PromptActionKind, title: String, foreground: Bool = false) -> UNNotificationAction {
        UNNotificationAction(
            identifier: actionIdentifier(kind),
            title: title,
            options: foreground ? [.foreground] : []
        )
    }
}
