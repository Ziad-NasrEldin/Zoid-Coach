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

    #expect(controller.health == denied)
    #expect(controller.statusMessage?.contains("Today") == true)
    #expect(service.requestCount == 1)
}

@MainActor
private final class RecordingNotificationDeliveryHealthService: NotificationDeliveryHealthServicing {
    let usesSystemSettingsRepair = true
    let health: SourceHealth
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
