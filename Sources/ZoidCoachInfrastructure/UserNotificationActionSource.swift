import Foundation
import UserNotifications
import ZoidCoachCore

public final class UserNotificationActionSource: NotificationSource, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func pending(identifier: String) async throws -> Bool {
        await center.pendingNotificationRequests().contains { $0.identifier == identifier }
    }

    public func schedule(_ desired: NotificationDesiredState) async throws -> String {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ActionSourceError.accessDenied
        }
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = desired.category
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
        try await center.add(UNNotificationRequest(identifier: desired.promptID, content: content, trigger: trigger))
        return desired.promptID
    }
}
