import Foundation
import UserNotifications
import ZoidCoachCore

@MainActor
protocol NotificationServicing: AnyObject {
    var isProductionAdapter: Bool { get }
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
}

@MainActor
final class NotificationService: NotificationServicing {
    let isProductionAdapter = true
    private let center: UNUserNotificationCenter?
    private let notificationIdentity: RuntimeNotificationIdentity

    init(
        center: UNUserNotificationCenter? = nil,
        runtimeEnvironment: RuntimeEnvironment = .production()
    ) {
        self.center = center
        notificationIdentity = runtimeEnvironment.identity.notification
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
                evidence: "One active prompt is used per daily decision",
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
                detail: "Notifications are unavailable",
                evidence: "Enable Zoid Coach notifications in System Settings",
                actionTitle: "Retry"
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
        content.title = "Zoid Coach"
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
    func inspect() async -> SourceHealth { health }
    func requestAccessAndInspect() async -> SourceHealth { health }

    private var health: SourceHealth {
        SourceHealth(
            id: .notifications,
            title: "macOS Notifications",
            eyebrow: "Escalation",
            state: .unavailable,
            detail: "QA notifications are disabled",
            evidence: "A dedicated QA notification adapter and namespace are required before notification access is enabled",
            actionTitle: "Unavailable"
        )
    }
}
