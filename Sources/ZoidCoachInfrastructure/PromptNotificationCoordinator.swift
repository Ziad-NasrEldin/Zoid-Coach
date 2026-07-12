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
    private let notificationIdentity: RuntimeNotificationIdentity
    private let onResponse: @Sendable (PromptResponseResult) async -> Void

    public init(
        promptStore: PromptInboxStore,
        center: UNUserNotificationCenter = .current(),
        runtimeEnvironment: RuntimeEnvironment = .production(),
        onResponse: @escaping @Sendable (PromptResponseResult) async -> Void = { _ in }
    ) {
        self.promptStore = promptStore
        self.center = center
        notificationIdentity = runtimeEnvironment.identity.notification
        self.onResponse = onResponse
        super.init()
    }

    public func activate() {
        center.delegate = self
        center.setNotificationCategories(Self.categories(notificationIdentity: notificationIdentity))
    }

    @discardableResult
    public func schedule(_ episode: PromptEpisode, deliveryDate: Date? = nil) async throws -> Bool {
        guard let category = PromptNotificationCategory.forPromptType(episode.type) else { return false }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return false }
        let content = UNMutableNotificationContent()
        content.title = episode.title
        content.body = episode.summary
        content.categoryIdentifier = notificationIdentity.promptCategoryIdentifier(category.rawValue)
        content.sound = .default
        content.userInfo = ["promptID": episode.id]
        let trigger: UNNotificationTrigger?
        if let deliveryDate, deliveryDate > Date() {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deliveryDate.timeIntervalSinceNow), repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(
            identifier: notificationIdentity.promptRequestPrefix + episode.id,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
        return true
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let promptID = response.notification.request.content.userInfo["promptID"] as? String,
              let action = Self.actionKind(
                identifier: response.actionIdentifier,
                notificationIdentity: notificationIdentity
              )
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
        actionIdentifier(action, notificationIdentity: RuntimeIdentity.production.notification)
    }

    public static func actionKind(identifier: String) -> PromptActionKind? {
        actionKind(identifier: identifier, notificationIdentity: RuntimeIdentity.production.notification)
    }

    public static func actionIdentifier(
        _ action: PromptActionKind,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> String {
        notificationIdentity.promptActionPrefix + action.rawValue.uppercased()
    }

    public static func actionKind(
        identifier: String,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> PromptActionKind? {
        guard identifier.hasPrefix(notificationIdentity.promptActionPrefix) else { return nil }
        return PromptActionKind(
            rawValue: String(identifier.dropFirst(notificationIdentity.promptActionPrefix.count)).lowercased()
        )
    }

    private static func categories(
        notificationIdentity: RuntimeNotificationIdentity
    ) -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.planReady.rawValue),
                actions: [
                    action(.acceptPlan, title: "Accept", notificationIdentity: notificationIdentity),
                    action(.reviewPlan, title: "Review", foreground: true, notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.meetingCandidate.rawValue),
                actions: [
                    action(.addMeeting, title: "Add", notificationIdentity: notificationIdentity),
                    action(.editMeeting, title: "Edit", foreground: true, notificationIdentity: notificationIdentity),
                    action(.ignore, title: "Ignore", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.planChanged.rawValue),
                actions: [
                    action(.reviewPlan, title: "Review", foreground: true, notificationIdentity: notificationIdentity),
                    action(.undoPlanChange, title: "Undo", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.wakeIntervention.rawValue),
                actions: [],
                intentIdentifiers: []
            )
        ]
    }

    private static func action(
        _ kind: PromptActionKind,
        title: String,
        foreground: Bool = false,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> UNNotificationAction {
        UNNotificationAction(
            identifier: actionIdentifier(kind, notificationIdentity: notificationIdentity),
            title: title,
            options: foreground ? [.foreground] : []
        )
    }
}
