import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class QANotificationReplacementProbeController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var latestPhase: QANotificationReplacementProbePhase?
    @Published private(set) var message = "Create the original notification, then replace it with changed guidance."

    let isAvailable: Bool

    private var coordinator: PromptNotificationCoordinator?
    private var probe: QANotificationReplacementProbe?

    init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        isAvailable = QANotificationReplacementProbe.isAvailable(in: runtimeEnvironment)
        guard isAvailable else {
            coordinator = nil
            probe = nil
            return
        }
        do {
            let store = try PromptInboxStore(databaseURL: runtimeEnvironment.databaseURL)
            let coordinator = PromptNotificationCoordinator(
                promptStore: store,
                runtimeEnvironment: runtimeEnvironment
            )
            coordinator.activate()
            self.coordinator = coordinator
            probe = try QANotificationReplacementProbe(
                runtimeEnvironment: runtimeEnvironment,
                promptStore: store,
                notifications: coordinator,
                probeID: "zc-054-009-visible"
            )
            refresh()
        } catch {
            coordinator = nil
            probe = nil
            message = error.localizedDescription
        }
    }

    var canScheduleReplacement: Bool {
        latestPhase == .original && !isRunning
    }

    func scheduleOriginal() {
        perform { probe in
            let result = try await probe.scheduleOriginal()
            return result.scheduled
                ? "Original notification delivered. Replace it with the updated guidance."
                : "Original prompt is in Today, but macOS did not accept the notification."
        }
    }

    func scheduleReplacement() {
        perform { probe in
            let result = try await probe.scheduleReplacement()
            return result.scheduled
                ? "Replacement accepted. Notification Center should show only the updated guidance."
                : "Updated prompt is in Today, but macOS did not accept the replacement."
        }
    }

    func refresh() {
        guard let probe, !isRunning else { return }
        Task {
            do {
                let snapshot = try await probe.snapshot()
                latestPhase = snapshot.latestPhase
                if let response = snapshot.latestResponse {
                    message = "Newest notification action recorded: \(response.action.rawValue)."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func perform(
        _ operation: @escaping @Sendable (QANotificationReplacementProbe) async throws -> String
    ) {
        guard let probe, !isRunning else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            do {
                message = try await operation(probe)
                latestPhase = try await probe.snapshot().latestPhase
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct QANotificationReplacementProbeView: View {
    @StateObject private var controller: QANotificationReplacementProbeController

    init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        _controller = StateObject(
            wrappedValue: QANotificationReplacementProbeController(
                runtimeEnvironment: runtimeEnvironment
            )
        )
    }

    var body: some View {
        if controller.isAvailable {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("SIGNED QA - NOTIFICATION REPLACEMENT")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                Text("This isolated check creates one coaching notification, then replaces it with newer content for the same logical decision.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("CREATE ORIGINAL") { controller.scheduleOriginal() }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                        .disabled(controller.isRunning)
                        .accessibilityIdentifier("settings.qa-notification-replacement.original")
                    Button("REPLACE WITH UPDATE") { controller.scheduleReplacement() }
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                        .disabled(!controller.canScheduleReplacement)
                        .accessibilityIdentifier("settings.qa-notification-replacement.updated")
                    Button("REFRESH RESULT") { controller.refresh() }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                        .disabled(controller.isRunning)
                        .accessibilityIdentifier("settings.qa-notification-replacement.refresh")
                }
                Text(controller.message)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.qa-notification-replacement.status")
            }
            .accessibilityIdentifier("settings.qa-notification-replacement")
        }
    }
}
