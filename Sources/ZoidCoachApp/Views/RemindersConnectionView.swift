import SwiftUI
import ZoidCoachInfrastructure

struct RemindersConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: RemindersConnectionController
    @StateObject private var deletedReminderController: DeletedReminderDecisionController
    @State private var removalCandidate: DeletedReminderDecision?
    let isLocalOnlyPlanningSelected: Bool
    let useLocalOnlyPlanning: () -> Void

    init(
        controller: @autoclosure @escaping () -> RemindersConnectionController = RemindersConnectionController(),
        deletedReminderController: @autoclosure @escaping () -> DeletedReminderDecisionController = DeletedReminderDecisionController(),
        isLocalOnlyPlanningSelected: Bool = false,
        useLocalOnlyPlanning: @escaping () -> Void
    ) {
        _controller = StateObject(wrappedValue: controller())
        _deletedReminderController = StateObject(wrappedValue: deletedReminderController())
        self.isLocalOnlyPlanningSelected = isLocalOnlyPlanningSelected
        self.useLocalOnlyPlanning = useLocalOnlyPlanning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                statusMark

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.ink)
                    Text(statusDetail)
                        .font(Sumi.body(12))
                        .foregroundStyle(statusNeedsAttention ? Sumi.sealDeep : Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let lastSuccessfulSync = controller.lastSuccessfulSync {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("LAST SUCCESS")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.muted)
                        Text(lastSuccessfulSync.formatted(date: .abbreviated, time: .shortened))
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Last successful Reminders sync "
                            + lastSuccessfulSync.formatted(date: .long, time: .shortened)
                    )
                    .accessibilityIdentifier("settings.reminders.connection.last-success")
                }
            }

            HStack(spacing: 10) {
                primaryAction

                if controller.needsPermissionRepair {
                    Button("OPEN SYSTEM SETTINGS") {
                        _ = controller.openPermissionSettings()
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .accessibilityIdentifier("settings.reminders.connection.repair")
                }

                if statusNeedsAttention {
                    Button(
                        isLocalOnlyPlanningSelected
                            ? "LOCAL-ONLY PLANNING SELECTED"
                            : "USE LOCAL-ONLY PLANNING",
                        action: useLocalOnlyPlanning
                    )
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                        .disabled(isLocalOnlyPlanningSelected)
                        .accessibilityValue(isLocalOnlyPlanningSelected ? "Selected" : "Not selected")
                        .accessibilityIdentifier("settings.reminders.connection.local-only")
                }
            }

            if let repairDetail = controller.repairDetail {
                Text(repairDetail)
                    .font(Sumi.body(11))
                    .foregroundStyle(controller.needsPermissionRepair ? Sumi.sealDeep : Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.reminders.connection.repair-detail")
            }

            deletedReminderChoices
        }
        .task {
            if case .idle = controller.state {
                await controller.refresh()
            }
            deletedReminderController.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await controller.applicationDidBecomeActive() }
            deletedReminderController.refresh()
        }
        .alert(removalConfirmation.title, isPresented: Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
        )) {
            Button("CANCEL", role: .cancel) { removalCandidate = nil }
            Button("REMOVE LOCAL COPY", role: .destructive) {
                guard let removalCandidate else { return }
                deletedReminderController.removeConfirmed(removalCandidate)
                self.removalCandidate = nil
            }
        } message: {
            Text(removalConfirmation.message)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await controller.applicationDidBecomeActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await controller.applicationDidBecomeActive() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.reminders.connection")
    }

    private var removalConfirmation: DeletedReminderRemovalConfirmation {
        DeletedReminderRemovalConfirmation(
            decision: removalCandidate ?? DeletedReminderDecision(
                sourceID: "none",
                title: "this task",
                dueDate: nil,
                listName: nil,
                deletedAt: .distantPast,
                state: .pending,
                decidedAt: nil
            )
        )
    }

    @ViewBuilder
    private var deletedReminderChoices: some View {
        if !deletedReminderController.decisions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("DELETED REMINDER CHOICES")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                Text("Choose whether each task should remain as local history. Zoid 666 stores only the task title, list name, and due date shown here.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(deletedReminderController.decisions) { decision in
                    let presentation = DeletedReminderDecisionPresentation(decision: decision)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(presentation.title).font(Sumi.body(13))
                            Spacer()
                            Text(presentation.status)
                                .font(Sumi.label(9))
                                .sumiLabelTracking()
                                .foregroundStyle(decision.state == .kept ? Sumi.okay : Sumi.sealDeep)
                        }
                        Text(presentation.detail)
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if decision.state == .pending {
                            HStack(spacing: 8) {
                                Button("KEEP LOCAL HISTORY") { deletedReminderController.keep(decision) }
                                    .buttonStyle(SumiActionButtonStyle(role: .accent, size: .compact))
                                    .accessibilityIdentifier(presentation.keepAccessibilityID)
                                Button("REMOVE LOCAL COPY") { removalCandidate = decision }
                                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                                    .accessibilityIdentifier(presentation.removeAccessibilityID)
                            }
                            .disabled(deletedReminderController.isWorking)
                        }
                    }
                    .padding(12)
                    .background(Sumi.paper)
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(presentation.rowAccessibilityID)
                }

                if let feedback = deletedReminderController.feedback {
                    Text(feedback).font(Sumi.body(11)).foregroundStyle(Sumi.okay)
                        .accessibilityIdentifier("settings.reminders.deleted.feedback")
                }
                if let errorMessage = deletedReminderController.errorMessage {
                    deletedReminderError(errorMessage)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.reminders.deleted-choices")
        } else if let errorMessage = deletedReminderController.errorMessage {
            deletedReminderError(errorMessage)
        }
    }

    private func deletedReminderError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.sealDeep)
                .accessibilityIdentifier("settings.reminders.deleted.error")
            Button("RELOAD DELETED REMINDER CHOICES") {
                deletedReminderController.refresh()
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .disabled(deletedReminderController.isWorking)
            .accessibilityIdentifier("settings.reminders.deleted.reload")
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch controller.state {
        case .idle, .connected, .refreshFailed:
            Button("REFRESH REMINDERS") {
                Task { await controller.refresh() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityIdentifier("settings.reminders.connection.refresh")
        case .permissionReady:
            Button("REQUEST ACCESS") {
                Task { await controller.connect() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
            .accessibilityIdentifier("settings.reminders.connection.connect")
        case .permissionRequired:
            Button("RECHECK ACCESS") {
                Task { await controller.refresh() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
            .accessibilityIdentifier("settings.reminders.connection.recheck")
        case .checking:
            ProgressView("Checking Apple Reminders")
                .accessibilityIdentifier("settings.reminders.connection.checking")
        }
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: "NOT CHECKED"
        case .checking: "CHECKING"
        case .connected: "CONNECTED"
        case .permissionReady: "READY TO CONNECT"
        case .permissionRequired: "ACCESS NEEDED"
        case .refreshFailed: "REFRESH FAILED"
        }
    }

    private var statusDetail: String {
        switch controller.state {
        case .idle:
            return "Check access and task freshness without changing any Reminder."
        case .checking:
            return "Reading current permission and incomplete task metadata."
        case let .connected(taskCount):
            let noun = taskCount == 1 ? "task" : "tasks"
            return "Apple Reminders returned " + taskCount.formatted() + " incomplete " + noun + "."
        case let .permissionReady(detail), let .permissionRequired(detail), let .refreshFailed(detail):
            return detail
        }
    }

    private var statusNeedsAttention: Bool {
        switch controller.state {
        case .permissionReady, .permissionRequired, .refreshFailed: true
        case .idle, .checking, .connected: false
        }
    }

    private var statusMark: some View {
        Image(systemName: statusSymbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(statusNeedsAttention ? Sumi.paper : Sumi.ink)
            .frame(width: 24, height: 24)
            .background(statusNeedsAttention ? Sumi.seal : Sumi.paper)
            .overlay { Rectangle().stroke(statusNeedsAttention ? Sumi.seal : Sumi.rule, lineWidth: 1) }
            .accessibilityHidden(true)
    }

    private var statusSymbol: String {
        switch controller.state {
        case .connected: "checkmark"
        case .permissionReady: "link"
        case .permissionRequired, .refreshFailed: "exclamationmark"
        case .idle: "minus"
        case .checking: "ellipsis"
        }
    }
}
