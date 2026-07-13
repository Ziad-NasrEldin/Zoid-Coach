import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachInfrastructure

@MainActor
@Test func notificationDeliveryHealthShowsAccessAndLocalHistory() async {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let service = RecordingNotificationDeliveryHealthService(
        health: SourceHealth(
            id: .notifications,
            title: "macOS Notifications",
            eyebrow: "Escalation",
            state: .healthy,
            detail: "Notifications are available",
            evidence: "macOS accepted the last prompt",
            actionTitle: "Inspect"
        ),
        records: [
            NotificationDeliveryRecord(
                id: 1,
                requestIdentifier: "private-request-id",
                promptID: "private-prompt-id",
                category: "PLAN_READY",
                outcome: .acceptedBySystem,
                scheduledFor: nil,
                recordedAt: date,
                attempt: 2,
                replacedPriorRequest: true,
                redactedError: nil
            )
        ]
    )
    let controller = NotificationDeliveryHealthController(service: service)

    await controller.refresh()

    #expect(controller.health?.state == .healthy)
    #expect(controller.records.count == 1)
    #expect(controller.records[0].replacedPriorRequest)
    #expect(service.inspectCount == 1)
}

@MainActor
@Test func notificationPermissionDenialKeepsTodayFallbackCopy() async {
    let denied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .attention,
        detail: "Notifications are unavailable",
        evidence: "Use Today",
        actionTitle: "Retry"
    )
    let service = RecordingNotificationDeliveryHealthService(health: denied, records: [])
    let controller = NotificationDeliveryHealthController(service: service)

    await controller.requestAccess()
    await controller.requestAccess()

    #expect(controller.health == denied)
    #expect(controller.statusMessage?.contains("Today") == true)
    #expect(service.requestCount == 1)
}

@MainActor
@Test func returningFromNotificationSettingsRechecksWithoutRequestingAgain() async {
    let denied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .attention,
        detail: "Notifications are off",
        evidence: "Today remains available",
        actionTitle: "Open Settings"
    )
    let granted = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .healthy,
        detail: "Notifications are available",
        evidence: "Delivery is enabled",
        actionTitle: "Inspect"
    )
    let service = RecordingNotificationDeliveryHealthService(health: denied, records: [])
    var opened: URL?
    let controller = NotificationDeliveryHealthController(service: service, openURL: {
        opened = $0
        return true
    })
    await controller.refresh()
    #expect(controller.openSystemSettings())
    #expect(opened?.absoluteString.contains("Notifications") == true)

    service.health = granted
    await controller.applicationDidBecomeActive()

    #expect(controller.health == granted)
    #expect(service.inspectCount == 2)
    #expect(service.requestCount == 0)
    #expect(controller.statusMessage == "Notifications are enabled. Timely prompts can use Notification Center, and every unresolved choice also remains available in Today.")
}

@MainActor
@Test func returningFromNotificationSettingsStillDeniedKeepsExactRepairAndFallbackGuidance() async {
    let denied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .attention,
        detail: "Notifications are off",
        evidence: "Today remains available",
        actionTitle: "Open Settings"
    )
    let service = RecordingNotificationDeliveryHealthService(health: denied, records: [])
    let controller = NotificationDeliveryHealthController(service: service, openURL: { _ in true })

    await controller.refresh()
    #expect(controller.openSystemSettings())
    await controller.applicationDidBecomeActive()

    #expect(controller.health == denied)
    #expect(controller.statusMessage == "Notifications are still off. In System Settings, choose Notifications, choose Zoid 666, and turn on Allow notifications. You can continue responding through Today meanwhile.")
    #expect(service.inspectCount == 2)
    #expect(service.requestCount == 0)
}

@MainActor
@Test func unrelatedForegroundRefreshDoesNotClaimAPermissionRepairAttempt() async {
    let denied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .attention,
        detail: "Notifications are off",
        evidence: "Today remains available",
        actionTitle: "Open Settings"
    )
    let service = RecordingNotificationDeliveryHealthService(health: denied, records: [])
    let controller = NotificationDeliveryHealthController(service: service)

    await controller.refresh()
    await controller.applicationDidBecomeActive()

    #expect(controller.statusMessage == nil)
    #expect(service.inspectCount == 2)
}

@MainActor
@Test func notificationSettingsFailureLeavesExactManualRecoveryPath() async {
    let denied = SourceHealth(
        id: .notifications,
        title: "macOS Notifications",
        eyebrow: "Escalation",
        state: .attention,
        detail: "Notifications are off",
        evidence: "Today remains available",
        actionTitle: "Open Settings"
    )
    let service = RecordingNotificationDeliveryHealthService(health: denied, records: [])
    let controller = NotificationDeliveryHealthController(
        service: service,
        openURL: { _ in false }
    )
    await controller.refresh()

    #expect(!controller.openSystemSettings())
    #expect(controller.statusMessage == "Open System Settings, choose Notifications, then choose Zoid 666.")
}

@MainActor
private final class RecordingNotificationDeliveryHealthService: NotificationDeliveryHealthServicing {
    let usesSystemSettingsRepair = true
    var health: SourceHealth
    let records: [NotificationDeliveryRecord]
    private(set) var inspectCount = 0
    private(set) var requestCount = 0

    init(health: SourceHealth, records: [NotificationDeliveryRecord]) {
        self.health = health
        self.records = records
    }

    func inspect() async -> SourceHealth {
        inspectCount += 1
        return health
    }

    func requestAccessAndInspect() async -> SourceHealth {
        requestCount += 1
        return health
    }

    func recentDeliveryRecords(limit _: Int) -> [NotificationDeliveryRecord] {
        records
    }
}
