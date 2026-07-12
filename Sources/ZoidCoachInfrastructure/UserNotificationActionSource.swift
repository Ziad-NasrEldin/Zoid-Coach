import Foundation
import UserNotifications
import ZoidCoachCore

public final class UserNotificationActionSource: NotificationSource, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let notificationIdentity: RuntimeNotificationIdentity

    public init(
        center: UNUserNotificationCenter = .current(),
        runtimeEnvironment: RuntimeEnvironment = .production()
    ) {
        self.center = center
        notificationIdentity = runtimeEnvironment.identity.notification
    }

    public func pending(identifier: String) async throws -> Bool {
        let requestIdentifier = namespacedRequestIdentifier(identifier)
        return await center.pendingNotificationRequests().contains { $0.identifier == requestIdentifier }
    }

    public func schedule(_ desired: NotificationDesiredState) async throws -> String {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ActionSourceError.accessDenied
        }
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = notificationIdentity.promptCategoryIdentifier(desired.category)
        content.title = desired.title
        content.body = desired.body
        content.sound = .default
        content.userInfo = ["promptID": desired.promptID]
        let trigger: UNNotificationTrigger?
        if let deliveryDate = desired.deliveryDate {
            let interval = max(1, deliveryDate.timeIntervalSinceNow)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        } else {
            trigger = nil
        }
        let requestIdentifier = namespacedRequestIdentifier(desired.promptID)
        try await center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger))
        return requestIdentifier
    }

    private func namespacedRequestIdentifier(_ identifier: String) -> String {
        guard !notificationIdentity.actionRequestPrefix.isEmpty,
              !identifier.hasPrefix(notificationIdentity.actionRequestPrefix) else { return identifier }
        return notificationIdentity.actionRequestPrefix + identifier
    }
}
