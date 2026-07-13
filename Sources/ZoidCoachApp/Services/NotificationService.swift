import Foundation
import UserNotifications
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
protocol NotificationServicing: AnyObject {
    var isProductionAdapter: Bool { get }
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
    func scheduleAcceptedBreakReminder(taskID: String, taskTitle: String, after seconds: TimeInterval) async throws
    func cancelAcceptedBreakReminder(taskID: String)
}

extension NotificationServicing {
    func scheduleAcceptedBreakReminder(taskID: String, taskTitle: String, after seconds: TimeInterval) async throws {}
    func cancelAcceptedBreakReminder(taskID: String) {}
}

@MainActor
final class NotificationService: NotificationServicing {
    let isProductionAdapter = true
    private let center: UNUserNotificationCenter?
    private let notificationIdentity: RuntimeNotificationIdentity
    private let deliveryLedger: NotificationDeliveryLedger?

    init(
        center: UNUserNotificationCenter? = nil,
        runtimeEnvironment: RuntimeEnvironment = .production()
    ) {
        self.center = center
        notificationIdentity = runtimeEnvironment.identity.notification
        deliveryLedger = try? NotificationDeliveryLedger(databaseURL: runtimeEnvironment.databaseURL)
    }

    private var notificationCenter: UNUserNotificationCenter { center ?? .current() }
    private var isRunningInSwiftPackageTests: Bool {
        Bundle.main.bundleURL.path.contains("swift/pm")
    }

    func inspect() async -> SourceHealth {
        guard !isRunningInSwiftPackageTests else {
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .notConnected,
                detail: "Notification checks are unavailable in the test host",
                evidence: "Production notification permissions are not touched by tests",
                actionTitle: "Connect"
            )
        }
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .healthy,
                detail: "Plan and wake notifications are available",
                evidence: deliveryEvidence(fallback: "No delivery attempts have been recorded yet"),
                actionTitle: "Inspect"
            )
        case .notDetermined:
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .notConnected,
                detail: "Notification permission is ready to be requested",
                evidence: "Required for morning plans and bounded wake alerts",
                actionTitle: "Connect"
            )
        case .denied:
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .attention,
                detail: "Notifications are off. Every unresolved coaching choice remains available in Today.",
                evidence: deliveryEvidence(fallback: "Enable Zoid 666 in System Settings for timely delivery, or keep using Today without notifications."),
                actionTitle: "Open Settings"
            )
        @unknown default:
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .attention,
                detail: "Notification status is not recognized",
                evidence: "No wake notification was scheduled",
                actionTitle: "Inspect"
            )
        }
    }

    func recentDeliveryRecords(limit: Int = 12) -> [NotificationDeliveryRecord] {
        (try? deliveryLedger?.recent(limit: limit)) ?? []
    }

    private func deliveryEvidence(fallback: String) -> String {
        guard let record = try? deliveryLedger?.recent(limit: 1).first else { return fallback }
        let replacement = record.replacedPriorRequest ? "; replaced the earlier request for the same decision" : ""
        switch record.outcome {
        case .authorizationUnavailable:
            return "Last prompt used the Today fallback at \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))"
        case .acceptedBySystem:
            return "macOS accepted the last prompt at \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))\(replacement)"
        case .deliveredByFixture:
            return "The isolated QA fixture delivered the last prompt at \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))\(replacement)"
        case .schedulingFailed:
            return "The last prompt could not be scheduled at \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    func requestAccessAndInspect() async -> SourceHealth {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return SourceHealth(
                id: .notifications,
                title: "macOS Notifications",
                eyebrow: "Escalation",
                state: .attention,
                detail: "Notification permission request failed",
                evidence: "No notification was scheduled",
                actionTitle: "Retry"
            )
        }
        return await inspect()
    }

    func scheduleAcceptedBreakReminder(taskID: String, taskTitle: String, after seconds: TimeInterval) async throws {
        guard !isRunningInSwiftPackageTests else { return }
        let identifier = "\(notificationIdentity.wakeRequestPrefix)accepted-break.\(taskID)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = "Break complete"
        content.body = "Your accepted break from \(taskTitle) has ended. Resume when you are ready."
        content.sound = .default
        try await notificationCenter.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        ))
    }

    func cancelAcceptedBreakReminder(taskID: String) {
        let identifier = "\(notificationIdentity.wakeRequestPrefix)accepted-break.\(taskID)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func scheduleWake(for day: Date, policy: WakeUpPolicy, reason: String) async throws {
        let identifier = notificationIdentity.wakeRequestPrefix + dayKey(for: day)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        var triggerComponents = DateComponents()
        triggerComponents.calendar = calendar
        triggerComponents.timeZone = calendar.timeZone
        triggerComponents.year = dayComponents.year
        triggerComponents.month = dayComponents.month
        triggerComponents.day = dayComponents.day
        triggerComponents.hour = policy.windowStartHour
        triggerComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Zoid 666"
        content.body = "Wake for your main objective. \(reason)"
        content.sound = .default
        content.categoryIdentifier = notificationIdentity.wakeCategoryIdentifier
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
        try await notificationCenter.add(request)
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

@MainActor
final class DisabledQANotificationService: NotificationServicing {
    let isProductionAdapter = false
    private let detail: String

    init(detail: String = "QA notifications are disabled") {
        self.detail = detail
    }
    func inspect() async -> SourceHealth { health }
    func requestAccessAndInspect() async -> SourceHealth { health }

    private var health: SourceHealth {
        SourceHealth(
            id: .notifications,
            title: "macOS Notifications",
            eyebrow: "Escalation",
            state: .unavailable,
            detail: detail,
            evidence: "A dedicated QA notification adapter and namespace are required before notification access is enabled",
            actionTitle: "Unavailable"
        )
    }
}
