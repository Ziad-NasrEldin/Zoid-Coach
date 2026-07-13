import AppKit
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
protocol NotificationDeliveryHealthServicing: AnyObject {
    var usesSystemSettingsRepair: Bool { get }
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
    func recentDeliveryRecords(limit: Int) -> [NotificationDeliveryRecord]
}

extension NotificationService: NotificationDeliveryHealthServicing {
    var usesSystemSettingsRepair: Bool { true }
}

@MainActor
private final class QAFixtureNotificationDeliveryHealthService: NotificationDeliveryHealthServicing {
    let usesSystemSettingsRepair = false
    private let notifications: QAFixtureNotificationService
    private let ledger: NotificationDeliveryLedger?

    init(runtimeEnvironment: RuntimeEnvironment, adapter: DeterministicOSFixtureAdapters) {
        notifications = QAFixtureNotificationService(adapter: adapter)
        ledger = try? NotificationDeliveryLedger(databaseURL: runtimeEnvironment.databaseURL)
    }

    func inspect() async -> SourceHealth { await notifications.inspect() }
    func requestAccessAndInspect() async -> SourceHealth { await notifications.inspect() }
    func recentDeliveryRecords(limit: Int) -> [NotificationDeliveryRecord] {
        (try? ledger?.recent(limit: limit)) ?? []
    }
}

@MainActor
private final class UnavailableQANotificationDeliveryHealthService: NotificationDeliveryHealthServicing {
    let usesSystemSettingsRepair = false
    private let detail: String

    init(detail: String) { self.detail = detail }

    func inspect() async -> SourceHealth {
        SourceHealth(
            id: .notifications,
            title: "QA Notifications",
            eyebrow: "Escalation",
            state: .unavailable,
            detail: detail,
            evidence: "No production notification center was touched",
            actionTitle: "Unavailable"
        )
    }

    func requestAccessAndInspect() async -> SourceHealth { await inspect() }
    func recentDeliveryRecords(limit _: Int) -> [NotificationDeliveryRecord] { [] }
}

@MainActor
final class NotificationDeliveryHealthController: ObservableObject {
    @Published private(set) var health: SourceHealth?
    @Published private(set) var records: [NotificationDeliveryRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?
    private var awaitingSystemSettingsReturn = false

    private let service: any NotificationDeliveryHealthServicing
    private let openURL: (URL) -> Bool

    init(
        service: (any NotificationDeliveryHealthServicing)? = nil,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.service = service ?? Self.liveService()
        self.openURL = openURL
    }

    var usesSystemSettingsRepair: Bool { service.usesSystemSettingsRepair }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        health = await service.inspect()
        records = service.recentDeliveryRecords(limit: 12)
        statusMessage = nil
        isRefreshing = false
    }

    func requestAccess() async {
        guard !isRefreshing,
              health == nil || health?.state == .notConnected else { return }
        isRefreshing = true
        health = await service.requestAccessAndInspect()
        records = service.recentDeliveryRecords(limit: 12)
        statusMessage = health?.state == .healthy
            ? "Notifications are enabled. Every unresolved choice also remains available in Today."
            : "macOS did not enable notifications. Use System Settings or continue through Today."
        isRefreshing = false
    }

    func applicationDidBecomeActive() async {
        guard health != nil, !isRefreshing else { return }
        let wasAwaitingSystemSettingsReturn = awaitingSystemSettingsReturn
        awaitingSystemSettingsReturn = false
        await refresh()
        guard wasAwaitingSystemSettingsReturn else { return }
        if health?.state == .healthy {
            statusMessage = "Notifications are enabled. Timely prompts can use Notification Center, and every unresolved choice also remains available in Today."
        } else {
            statusMessage = "Notifications are still off. Open System Settings > Notifications > Zoid 666 > Allow notifications. You can continue responding through Today meanwhile."
        }
    }

    @discardableResult
    func openSystemSettings() -> Bool {
        guard service.usesSystemSettingsRepair else {
            awaitingSystemSettingsReturn = true
            statusMessage = "Apply the prepared QA notification permission control, then return to Zoid 666. Permission is checked automatically, Today remains available, and no production System Settings page is opened."
            return true
        }
        let addresses = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for address in addresses {
            if let url = URL(string: address), openURL(url) {
                awaitingSystemSettingsReturn = true
                statusMessage = "After changing access, return to Zoid 666. Permission is checked automatically, and Today remains available meanwhile."
                return true
            }
        }
        statusMessage = "Open System Settings > Notifications > Zoid 666 > Allow notifications."
        return false
    }

    private static func liveService() -> any NotificationDeliveryHealthServicing {
        let runtimeEnvironment = RuntimeEnvironment.current()
        guard case .qa = runtimeEnvironment.mode else { return NotificationService(runtimeEnvironment: runtimeEnvironment) }
        do {
            let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtimeEnvironment)
            return QAFixtureNotificationDeliveryHealthService(
                runtimeEnvironment: runtimeEnvironment,
                adapter: adapter
            )
        } catch {
            return UnavailableQANotificationDeliveryHealthService(
                detail: "QA fixture startup failed: \(error.localizedDescription)"
            )
        }
    }
}

struct NotificationDeliveryHealthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: NotificationDeliveryHealthController

    @MainActor
    init(controller: NotificationDeliveryHealthController = NotificationDeliveryHealthController()) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let health = controller.health {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(color(for: health.state))
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(health.detail)
                            .font(Sumi.body(13))
                            .foregroundStyle(Sumi.ink)
                        Text(health.evidence)
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(statusLabel(for: health.state))
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(health.state == .healthy ? Sumi.ink : Sumi.sealDeep)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.notifications.health")

                HStack(spacing: 10) {
                    if health.state == .notConnected {
                        Button("ENABLE NOTIFICATIONS") {
                            Task { await controller.requestAccess() }
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                        .accessibilityIdentifier("settings.notifications.enable")
                    }
                    if health.state == .attention || health.state == .unavailable {
                        Button(controller.usesSystemSettingsRepair ? "OPEN NOTIFICATION SETTINGS" : "APPLY QA REPAIR") {
                            controller.openSystemSettings()
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                        .accessibilityIdentifier("settings.notifications.repair")
                    }
                    Button(controller.isRefreshing ? "REFRESHING" : "REFRESH STATUS") {
                        Task { await controller.refresh() }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(controller.isRefreshing)
                    .keyboardShortcut("r", modifiers: [.option, .shift])
                    .accessibilityIdentifier("settings.notifications.refresh")
                }
            } else if controller.isRefreshing {
                ProgressView("Checking notification access...")
                    .accessibilityIdentifier("settings.notifications.loading")
            } else {
                Button("CHECK NOTIFICATION STATUS") {
                    Task { await controller.refresh() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityIdentifier("settings.notifications.check")
            }

            if let statusMessage = controller.statusMessage {
                Text(statusMessage)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.notifications.status-message")
            }

            Divider().overlay(Sumi.rule)

            VStack(alignment: .leading, spacing: 5) {
                Text("RECENT LOCAL DELIVERY RESULTS")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.sealDeep)
                Text("This history stores only delivery state, prompt category, and time. Notification titles, message text, and action content are not copied into the ledger. Records expire after 30 days.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.notifications.privacy")
            }

            if controller.records.isEmpty {
                Text("No notification delivery attempts have been recorded yet. Important choices still appear in Today.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("settings.notifications.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(controller.records) { record in
                        deliveryRow(record)
                        if record.id != controller.records.last?.id {
                            Divider().overlay(Sumi.rule)
                        }
                    }
                }
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.notifications.delivery-history")
            }
        }
        .task { await controller.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await controller.applicationDidBecomeActive() }
        }
    }

    private func deliveryRow(_ record: NotificationDeliveryRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(outcomeTitle(record.outcome))
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(record.outcome == .schedulingFailed ? Sumi.sealDeep : Sumi.ink)
                Text("\(categoryTitle(record.category)) · \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                if record.replacedPriorRequest {
                    Text("Replaced the earlier request for this same decision instead of stacking another notification.")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                }
                if record.outcome == .authorizationUnavailable {
                    Text("The unresolved choice remains available in Today.")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                }
            }
            Spacer(minLength: 8)
            Text("TRY \(record.attempt)")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.notifications.delivery.\(record.id)")
    }

    private func outcomeTitle(_ outcome: NotificationDeliveryOutcome) -> String {
        switch outcome {
        case .authorizationUnavailable: "TODAY FALLBACK"
        case .acceptedBySystem: "ACCEPTED BY MACOS"
        case .deliveredByFixture: "DELIVERED IN QA"
        case .schedulingFailed: "DELIVERY FAILED"
        }
    }

    private func categoryTitle(_ category: String) -> String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusLabel(for state: HealthState) -> String {
        switch state {
        case .healthy: "READY"
        case .checking: "CHECKING"
        case .notConnected: "NOT CONNECTED"
        case .attention: "ACCESS NEEDED"
        case .unavailable: "UNAVAILABLE"
        }
    }

    private func color(for state: HealthState) -> Color {
        switch state {
        case .healthy: Sumi.ink
        case .checking: Sumi.muted
        case .notConnected: Sumi.muted
        case .attention, .unavailable: Sumi.seal
        }
    }
}
