import AppKit
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol MenuBarTodayClient: Sendable {
    func fetchTodaySnapshot() async throws -> TodaySnapshot
    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot
}

extension TodayDashboardXPCClient: MenuBarTodayClient {}

@MainActor
final class MenuBarCoachController: ObservableObject {
    @Published private(set) var snapshot: TodaySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    private let client: any MenuBarTodayClient

    init(client: any MenuBarTodayClient = TodayDashboardXPCClient(runtimeEnvironment: .current())) {
        self.client = client
    }

    var state: MenuBarCoachState { MenuBarCoachState(snapshot: snapshot) }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchTodaySnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "Today could not be refreshed. Open Source Health and check the background agent."
        }
    }

    func apply(_ command: TaskActivityCommand, taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            snapshot = try await client.apply(command, taskID: taskID)
            errorMessage = nil
        } catch {
            errorMessage = "The task change was not saved. The last confirmed state is still shown."
        }
    }

    func startRecommendedTaskIfStillReady(taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let latest = try await client.fetchTodaySnapshot()
            snapshot = latest
            let latestState = MenuBarCoachState(snapshot: latest)
            guard latestState.activeTask == nil,
                  latestState.pausedTask == nil,
                  latestState.recommendedTask?.taskID == taskID
            else {
                errorMessage = "The recommended task changed before Start. Nothing was started. Review the current menu state and try again."
                return
            }

            let updated = try await client.apply(.start, taskID: taskID)
            let updatedState = MenuBarCoachState(snapshot: updated)
            guard updatedState.activeTask?.taskID == taskID,
                  updated.taskRows.first(where: { $0.taskID == taskID })?.state == .active
            else {
                errorMessage = "The background agent did not confirm that the task started. Refresh before trying again."
                return
            }

            snapshot = updated
            errorMessage = nil
        } catch {
            errorMessage = "The task was not started. The last confirmed state is still shown."
        }
    }

    func endWorkdayIfStillActive(taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let latest = try await client.fetchTodaySnapshot()
            snapshot = latest
            let activeID = MenuBarCoachState(snapshot: latest).activeTask?.taskID
            guard activeID == taskID else {
                errorMessage = "The active task changed before confirmation. Nothing was paused. Review the current task and try again."
                return
            }
            snapshot = try await client.apply(.pauseForEndOfDay, taskID: taskID)
            errorMessage = nil
        } catch {
            errorMessage = "The task change was not saved. The last confirmed state is still shown."
        }
    }
}

struct MenuBarCoachView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appModel: AppModel
    @ObservedObject var voiceModel: VoiceConversationModel
    @StateObject private var controller: MenuBarCoachController
    @StateObject private var pauseController: MenuBarCoachingPauseController
    @State private var pendingEndWorkdayTask: TodayTaskRow?

    @MainActor
    init(
        appModel: AppModel,
        voiceModel: VoiceConversationModel,
        controller: MenuBarCoachController = MenuBarCoachController(),
        pauseController: MenuBarCoachingPauseController = MenuBarCoachingPauseController()
    ) {
        self.appModel = appModel
        self.voiceModel = voiceModel
        _controller = StateObject(wrappedValue: controller)
        _pauseController = StateObject(wrappedValue: pauseController)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coachHeader
            notificationFallbackSection
            coachingPauseSection

            Divider().overlay(Sumi.rule)

            taskSection

            Divider().overlay(Sumi.rule)

            navigationSection

            Divider().overlay(Sumi.rule)

            DisclosureGroup("VOICE CONTROLS") {
                VoiceMenuView(model: voiceModel)
                    .padding(.top, 8)
            }
            .font(Sumi.label(9))
            .sumiLabelTracking()
            .padding(14)
        }
        .frame(width: 360)
        .background(Sumi.paper)
        .task {
            async let todayRefresh: Void = controller.refresh()
            async let pauseRefresh: Void = pauseController.refresh()
            async let fallbackRefresh: Void = appModel.refreshMenuBarPromptFallback()
            _ = await (todayRefresh, pauseRefresh, fallbackRefresh)
            await appModel.refreshTodaySnapshot()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-bar.coach")
        .confirmationDialog(
            "END THE WORKDAY?",
            isPresented: endWorkdayConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("END WORKDAY", role: .destructive) {
                guard let task = pendingEndWorkdayTask else { return }
                pendingEndWorkdayTask = nil
                Task {
                    await controller.endWorkdayIfStillActive(taskID: task.taskID)
                    await appModel.refreshTodaySnapshot()
                }
            }
            Button("KEEP WORKING", role: .cancel) {
                pendingEndWorkdayTask = nil
            }
        } message: {
            Text("The active task will pause and its tracked time will remain saved. You can resume it later from Today or this menu.")
        }
    }

    private var menuState: MenuBarCoachState {
        MenuBarCoachState(
            snapshot: controller.snapshot,
            coachingIsPaused: pauseController.isPaused,
            unresolvedPromptCount: appModel.promptEpisodes.count,
            notificationsUnavailable: notificationsUnavailable
        )
    }

    private var notificationsUnavailable: Bool {
        guard let notifications = appModel.sources.first(where: { $0.id == .notifications }) else {
            return false
        }
        return notifications.state == .attention
            || notifications.state == .notConnected
            || notifications.state == .unavailable
    }

    private var coachHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: menuState.menuBarSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(menuState.notificationFallbackIsActive || menuState.tone == .attention ? Sumi.seal : Sumi.ink)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("ZOID 666 / NOW")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.sealDeep)
                Text(menuState.tone.label)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.ink)
            }
            Spacer(minLength: 8)
            Button {
                Task { await refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(controller.isLoading || controller.isApplying)
            .help("Refresh Today state")
            .accessibilityLabel("Refresh menu bar state")
            .accessibilityIdentifier("menu-bar.refresh")
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(menuState.menuBarLabel)
        .accessibilityIdentifier("menu-bar.status")
    }

    private var coachingPauseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pauseController.isPaused ? "COACHING PAUSED" : "COACHING RUNNING")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(pauseController.isPaused ? Sumi.seal : Sumi.ink)
                    Text(pauseController.isPaused
                         ? "Behavior prompts and automatic actions are paused. Task tracking and Today stay available."
                         : pauseController.runningDetail)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Button(pauseController.isPaused ? "RESUME" : "PAUSE") {
                    Task {
                        await pauseController.setPaused(!pauseController.isPaused)
                        await controller.refresh()
                        await appModel.refreshTodaySnapshot()
                    }
                }
                .buttonStyle(SumiActionButtonStyle(
                    role: pauseController.isPaused ? .primary : .quiet,
                    size: .compact
                ))
                .disabled(pauseController.isLoading || pauseController.isSaving)
                .accessibilityLabel(pauseController.isPaused ? "Resume coaching" : pauseController.pauseActionAccessibilityLabel)
                .accessibilityIdentifier(pauseController.isPaused ? "menu-bar.coaching.resume" : "menu-bar.coaching.pause")
            }

            if pauseController.isSaving {
                ProgressView(pauseController.isPaused ? "Resuming coaching" : "Pausing coaching")
                    .controlSize(.small)
                    .accessibilityIdentifier("menu-bar.coaching.progress")
            }
            if let message = pauseController.statusMessage {
                Text(message)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.ink)
                    .accessibilityIdentifier("menu-bar.coaching.status")
            }
            if let error = pauseController.errorMessage {
                Text(error)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.sealDeep)
                    .accessibilityIdentifier("menu-bar.coaching.error")
            }
        }
        .padding(14)
        .background(pauseController.isPaused ? Sumi.sealWash : Sumi.softPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-bar.coaching-control")
    }

    @ViewBuilder
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let task = menuState.primaryTask {
                Text(task.title)
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.ink)
                    .lineLimit(2)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("menu-bar.task.title")
                if let activeCommitment = menuState.activeCommitment {
                    Text(activeCommitment.modeLabel)
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.sealDeep)
                        .accessibilityLabel(activeCommitment.accessibilitySummary)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("menu-bar.task.timing-mode")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(menuState.taskStatus(at: context.date))
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                            .accessibilityIdentifier("menu-bar.task.status")
                        Text(menuState.compactTaskFacts.joined(separator: " · "))
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("menu-bar.task.facts")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(menuState.compactTaskAccessibilitySummary(at: context.date) ?? "No active task")
                    .accessibilityIdentifier("menu-bar.task.summary")
                }

                HStack(spacing: 8) {
                    if menuState.activeTask != nil {
                        taskButton("PAUSE", identifier: "menu-bar.task.pause") {
                            await apply(.pauseDoneForNow, taskID: task.taskID)
                        }
                        taskButton("BREAK 15", role: .quiet, identifier: "menu-bar.task.break") {
                            await apply(.pauseForBreak, taskID: task.taskID)
                        }
                        taskButton("COMPLETE", role: .quiet, identifier: "menu-bar.task.complete") {
                            await apply(.complete, taskID: task.taskID)
                        }
                        .accessibilityLabel("Complete active task \(task.title)")
                    } else if menuState.pausedTask != nil {
                        taskButton(task.acceptedBreak == nil ? "RESUME" : "END BREAK", identifier: "menu-bar.task.resume") {
                            await apply(.resume, taskID: task.taskID)
                        }
                    } else {
                        taskButton("START", identifier: "menu-bar.task.start") {
                            await startRecommendedTask(taskID: task.taskID)
                        }
                        .accessibilityLabel("Start \(task.title)")
                        .accessibilityHint("Rechecks that this is still the recommended ready task before starting it.")
                    }
                    taskButton("OPEN TODAY", role: .quiet, identifier: "menu-bar.open-today") {
                        open(.today)
                    }
                }
                if menuState.canEndWorkday {
                    Button("END WORKDAY") {
                        pendingEndWorkdayTask = task
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                    .disabled(controller.isApplying)
                    .help("Pause this task and close the workday after confirmation")
                    .accessibilityIdentifier("menu-bar.task.end-workday")
                }
            } else {
                Text("No task is active or ready. Open Today to plan the next deliberate move.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu-bar.task.empty")
                taskButton("OPEN TODAY", identifier: "menu-bar.open-today") {
                    open(.today)
                }
            }

            if let attention = menuState.attentionDetail {
                Text(attention)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu-bar.attention")
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.seal)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu-bar.error")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var navigationSection: some View {
        HStack(spacing: 8) {
            taskButton("SOURCE HEALTH", role: .quiet, identifier: "menu-bar.open-source-health") {
                open(.diagnostics)
            }
            taskButton("SETTINGS", role: .quiet, identifier: "menu-bar.open-settings") {
                open(.settings)
            }
        }
        .padding(14)
    }

    private func taskButton(
        _ title: String,
        role: SumiActionRole = .primary,
        identifier: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(SumiActionButtonStyle(role: role, size: .compact))
            .disabled(controller.isApplying)
            .accessibilityIdentifier(identifier)
    }

    private func apply(_ command: TaskActivityCommand, taskID: String) async {
        await controller.apply(command, taskID: taskID)
        await appModel.refreshTodaySnapshot()
        await appModel.reconcileAcceptedBreakReminder(taskID: taskID)
    }

    private func startRecommendedTask(taskID: String) async {
        await controller.startRecommendedTaskIfStillReady(taskID: taskID)
        await appModel.refreshTodaySnapshot()
    }

    private func refreshAll() async {
        await controller.refresh()
        await appModel.refreshTodaySnapshot()
    }

    private func open(_ section: AppSection) {
        appModel.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.canBecomeKey && $0.level == .normal }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @ViewBuilder
    private var notificationFallbackSection: some View {
        if let detail = menuState.notificationFallbackDetail {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundStyle(Sumi.seal)
                        .accessibilityHidden(true)
                    Text(menuState.unresolvedPromptCount == 1 ? "DECISION WAITING" : "DECISIONS WAITING")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }

                Text(detail)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(menuState.unresolvedPromptCount == 1 ? "OPEN DECISION IN TODAY" : "OPEN DECISIONS IN TODAY") {
                    open(.today)
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                .accessibilityIdentifier("menu-bar.prompt-fallback.open-today")
            }
            .padding(14)
            .background(Sumi.sealWash)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menu-bar.prompt-fallback")

            Divider().overlay(Sumi.rule)
        }
    }

    private var endWorkdayConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingEndWorkdayTask != nil },
            set: { isPresented in
                if !isPresented { pendingEndWorkdayTask = nil }
            }
        )
    }
}
