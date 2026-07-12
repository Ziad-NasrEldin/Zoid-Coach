import AppKit
import SwiftUI
import ZoidCoachInfrastructure

@MainActor
protocol NotificationDeliveryHealthServicing: AnyObject {
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
    func recentDeliveryRecords(limit: Int) -> [NotificationDeliveryRecord]
}

extension NotificationService: NotificationDeliveryHealthServicing {}

@MainActor
final class NotificationDeliveryHealthController: ObservableObject {
    @Published private(set) var health: SourceHealth?
    @Published private(set) var records: [NotificationDeliveryRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?

    private let service: any NotificationDeliveryHealthServicing

    init(service: any NotificationDeliveryHealthServicing = NotificationService()) {
        self.service = service
    }

    func refresh() async {
        isRefreshing = true
        health = await service.inspect()
        records = service.recentDeliveryRecords(limit: 12)
        statusMessage = nil
        isRefreshing = false
    }

    func requestAccess() async {
        isRefreshing = true
        health = await service.requestAccessAndInspect()
        records = service.recentDeliveryRecords(limit: 12)
        statusMessage = health?.state == .healthy
            ? "Notifications are enabled. Every unresolved choice also remains available in Today."
            : "macOS did not enable notifications. Use System Settings or continue through Today."
        isRefreshing = false
    }

    func openSystemSettings() {
        let addresses = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for address in addresses {
            if let url = URL(string: address), NSWorkspace.shared.open(url) {
                statusMessage = "After changing access, return here and refresh status. Today remains available meanwhile."
                return
            }
        }
        statusMessage = "Open System Settings, choose Notifications, then choose Zoid 666."
    }
}

struct NotificationDeliveryHealthView: View {
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
                        Button("OPEN NOTIFICATION SETTINGS") {
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
