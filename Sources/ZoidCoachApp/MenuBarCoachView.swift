import AppKit
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol MenuBarTodayClient: Sendable {
    func fetchTodaySnapshot() async throws -> TodaySnapshot
    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot
    func blockTask(taskID: String, reason: String) async throws -> TodaySnapshot
}

extension TodayDashboardXPCClient: MenuBarTodayClient {}

enum MenuBarTaskSyncPresentation: Equatable {
    case loading
    case confirmed
    case stale
    case unavailable
}

@MainActor
final class MenuBarCoachController: ObservableObject {
    @Published private(set) var snapshot: TodaySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var syncPresentation: MenuBarTaskSyncPresentation = .loading
    @Published private(set) var lastConfirmedAt: Date?

    private let client: any MenuBarTodayClient

    init(client: any MenuBarTodayClient) {
        self.client = client
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment) {
        self.init(client: TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment))
    }

    var state: MenuBarCoachState { MenuBarCoachState(snapshot: snapshot) }

    func adoptLastKnownSnapshot(_ lastKnownSnapshot: TodaySnapshot?) {
        guard snapshot == nil, let lastKnownSnapshot else { return }
        snapshot = lastKnownSnapshot
        if lastConfirmedAt == nil {
            lastConfirmedAt = Date()
        }
        if syncPresentation == .unavailable {
            syncPresentation = .stale
            errorMessage = "Today could not be refreshed. The last confirmed task state remains visible. Open Source Health, then refresh."
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchTodaySnapshot()
            errorMessage = nil
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            if snapshot == nil {
                syncPresentation = .unavailable
                errorMessage = "Task state is unavailable because Zoid 666 could not load a confirmed state from the background agent. Open Source Health, then refresh."
            } else {
                syncPresentation = .stale
                errorMessage = "Today could not be refreshed. The last confirmed task state remains visible. Open Source Health, then refresh."
            }
        }
    }

    func apply(_ command: TaskActivityCommand, taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            snapshot = try await client.apply(command, taskID: taskID)
            errorMessage = nil
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            errorMessage = "The task change was not saved. The last confirmed state is still shown."
            syncPresentation = snapshot == nil ? .unavailable : .stale
        }
    }

    func block(taskID: String, reason: String) async {
        guard !isApplying else { return }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...240).contains(normalizedReason.count) else {
            errorMessage = "Enter a blocker reason between 3 and 240 characters. Nothing was changed."
            return
        }
        isApplying = true
        defer { isApplying = false }
        do {
            let updated = try await client.blockTask(taskID: taskID, reason: normalizedReason)
            guard let confirmed = updated.taskRows.first(where: { $0.taskID == taskID }),
                  confirmed.state == .blocked,
                  confirmed.blockedReason == normalizedReason
            else {
                errorMessage = "The background agent did not confirm the blocker. The last confirmed state is still shown."
                syncPresentation = snapshot == nil ? .unavailable : .stale
                return
            }
            snapshot = updated
            errorMessage = nil
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            errorMessage = "The blocker was not saved. The last confirmed state is still shown."
            syncPresentation = snapshot == nil ? .unavailable : .stale
        }
    }

    func switchTask(from activeTaskID: String, to targetTaskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let latest = try await client.fetchTodaySnapshot()
            snapshot = latest
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
            let latestState = MenuBarCoachState(snapshot: latest)
            guard latestState.activeTask?.taskID == activeTaskID,
                  latestState.switchCandidates.contains(where: { $0.taskID == targetTaskID })
            else {
                errorMessage = "The active task or switch target changed before confirmation. Nothing was switched. Review the current menu state and try again."
                return
            }

            let updated = try await client.apply(.start, taskID: targetTaskID)
            let updatedState = MenuBarCoachState(snapshot: updated)
            guard updatedState.activeTask?.taskID == targetTaskID,
                  updated.taskRows.first(where: { $0.taskID == activeTaskID })?.state == .paused
            else {
                errorMessage = "The background agent did not confirm the complete task switch. Refresh before trying again."
                syncPresentation = .stale
                return
            }

            snapshot = updated
            errorMessage = nil
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            errorMessage = "The task switch was not saved. The last confirmed state is still shown."
            syncPresentation = snapshot == nil ? .unavailable : .stale
        }
    }

    func startRecommendedTaskIfStillReady(taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let latest = try await client.fetchTodaySnapshot()
            snapshot = latest
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
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
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            errorMessage = "The task was not started. The last confirmed state is still shown."
            syncPresentation = snapshot == nil ? .unavailable : .stale
        }
    }

    func endWorkdayIfStillActive(taskID: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let latest = try await client.fetchTodaySnapshot()
            snapshot = latest
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
            let activeID = MenuBarCoachState(snapshot: latest).activeTask?.taskID
            guard activeID == taskID else {
                errorMessage = "The active task changed before confirmation. Nothing was paused. Review the current task and try again."
                return
            }
            snapshot = try await client.apply(.pauseForEndOfDay, taskID: taskID)
            errorMessage = nil
            syncPresentation = .confirmed
            lastConfirmedAt = Date()
        } catch {
            errorMessage = "The task change was not saved. The last confirmed state is still shown."
            syncPresentation = snapshot == nil ? .unavailable : .stale
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
    @State private var pendingBlockedTask: TodayTaskRow?
    @State private var pendingSwitchTask: TodayTaskRow?
    @State private var blockReason = ""

    @MainActor
    init(
        appModel: AppModel,
        voiceModel: VoiceConversationModel,
        controller: MenuBarCoachController,
        pauseController: MenuBarCoachingPauseController
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

            if pauseController.usesManualWorkday {
                manualWorkdaySection
            }

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
            controller.adoptLastKnownSnapshot(appModel.todaySnapshot)
            async let todayRefresh: Void = controller.refresh()
            async let pauseRefresh: Void = pauseController.refresh()
            async let fallbackRefresh: Void = appModel.refreshMenuBarPromptFallback()
            _ = await (todayRefresh, pauseRefresh, fallbackRefresh)
            await appModel.refreshTodaySnapshot()
        }
        .onChange(of: appModel.todaySnapshot) { _, snapshot in
            controller.adoptLastKnownSnapshot(snapshot)
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
        .sheet(item: $pendingBlockedTask) { task in
            TaskBlockReasonSheet(taskTitle: task.title, reason: $blockReason) {
                let reason = blockReason
                pendingBlockedTask = nil
                blockReason = ""
                Task {
                    await controller.block(taskID: task.taskID, reason: reason)
                    await appModel.refreshTodaySnapshot()
                }
            }
        }
        .confirmationDialog(
            "SWITCH ACTIVE TASK?",
            isPresented: switchConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("SWITCH TASK") {
                guard let activeTask = menuState.activeTask,
                      let targetTask = pendingSwitchTask
                else { return }
                pendingSwitchTask = nil
                Task {
                    await controller.switchTask(
                        from: activeTask.taskID,
                        to: targetTask.taskID
                    )
                    await appModel.refreshTodaySnapshot()
                }
            }
            Button("KEEP CURRENT TASK", role: .cancel) {
                pendingSwitchTask = nil
            }
        } message: {
            Text("The current task will pause as Switching tasks. Its tracked time will be preserved, and \"\(pendingSwitchTask?.title ?? "the selected task")\" will start.")
        }
    }

    private var menuState: MenuBarCoachState {
        MenuBarCoachState(
            snapshot: controller.snapshot,
            snapshotConfirmedAt: controller.lastConfirmedAt,
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

    private var manualWorkdaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MANUAL WORKDAY")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.sealDeep)
            Text(manualWorkdayDetail)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Sumi.softPaper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menu-bar.manual-workday.status")
    }

    private var manualWorkdayDetail: String {
        if menuState.workdayHasEnded {
            return "Your workday is ended and tracked time is saved. Start or resume a task when you are ready to begin again."
        }
        if menuState.activeTask != nil || menuState.pausedTask != nil {
            return "Your workday is active. Use End Workday below when you are finished; fixed hours will not end it for you."
        }
        return "Your workday begins only when you start or resume a task. Fixed hours will not start it for you."
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

                        if let comparison = menuState.activeTimeComparison(at: context.date) {
                            MenuBarActiveTimeComparisonView(comparison: comparison)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(menuState.availableTaskActions) { action in
                        taskActionButton(action, task: task)
                    }
                }
            } else if controller.syncPresentation == .loading {
                ProgressView("Loading confirmed task state")
                    .controlSize(.small)
                    .accessibilityIdentifier("menu-bar.task.loading")
            } else if controller.syncPresentation == .unavailable {
                Text("Task state is unavailable. Zoid 666 has not confirmed whether a task is active.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu-bar.task.unavailable")
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
            .frame(maxWidth: .infinity)
            .disabled(controller.isApplying)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func taskActionButton(_ action: MenuBarTaskAction, task: TodayTaskRow) -> some View {
        switch action {
        case .start:
            taskButton(pauseController.usesManualWorkday ? "START WORKDAY" : "START", identifier: "menu-bar.task.start") {
                await startRecommendedTask(taskID: task.taskID)
            }
            .accessibilityLabel(pauseController.usesManualWorkday ? "Start workday with recommended task" : action.accessibilityLabel)
            .accessibilityHint("Rechecks that this is still the recommended ready task before starting it.")
        case .pause:
            taskButton("PAUSE", identifier: "menu-bar.task.pause") {
                await apply(.pauseDoneForNow, taskID: task.taskID)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .resume, .endBreak:
            taskButton(resumeActionTitle(action), identifier: "menu-bar.task.resume") {
                await apply(.resume, taskID: task.taskID)
            }
            .accessibilityLabel(resumeActionAccessibilityLabel(action))
        case .startBreak:
            taskButton("BREAK 15", role: .quiet, identifier: "menu-bar.task.break") {
                await apply(.pauseForBreak, taskID: task.taskID)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .complete:
            taskButton("COMPLETE", role: .quiet, identifier: "menu-bar.task.complete") {
                await apply(.complete, taskID: task.taskID)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .markBlocked:
            Button("BLOCKED") {
                blockReason = task.blockedReason ?? ""
                pendingBlockedTask = task
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .frame(maxWidth: .infinity)
            .disabled(controller.isApplying)
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityIdentifier("menu-bar.task.block")
        case .switchTask:
            Menu("SWITCH") {
                ForEach(menuState.switchCandidates) { candidate in
                    Button(candidate.title) {
                        pendingSwitchTask = candidate
                    }
                    .accessibilityLabel("Switch to \(candidate.title)")
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)
            .disabled(controller.isApplying)
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityIdentifier("menu-bar.task.switch")
        case .openToday:
            taskButton("OPEN TODAY", role: .quiet, identifier: "menu-bar.open-today") {
                open(.today)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .endWorkday:
            Button("END WORKDAY") {
                pendingEndWorkdayTask = task
            }
            .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
            .frame(maxWidth: .infinity)
            .disabled(controller.isApplying)
            .help("Pause this task and close the workday after confirmation")
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityIdentifier("menu-bar.task.end-workday")
        }
    }

    private func resumeActionTitle(_ action: MenuBarTaskAction) -> String {
        if pauseController.usesManualWorkday, menuState.workdayHasEnded {
            return "START WORKDAY"
        }
        return action == .resume ? "RESUME" : "END BREAK"
    }

    private func resumeActionAccessibilityLabel(_ action: MenuBarTaskAction) -> String {
        if pauseController.usesManualWorkday, menuState.workdayHasEnded {
            return "Start workday by resuming paused task"
        }
        return action.accessibilityLabel
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

    private var switchConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingSwitchTask != nil },
            set: { isPresented in
                if !isPresented { pendingSwitchTask = nil }
            }
        )
    }
}
