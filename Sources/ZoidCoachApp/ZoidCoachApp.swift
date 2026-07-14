import AppKit
import Darwin
import SwiftUI
import ZoidCoachCore

@main
struct ZoidCoachApplication: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var voiceModel: VoiceConversationModel
    @StateObject private var onboarding: OnboardingCoordinator
    @StateObject private var agentLifecycle: AgentLifecycleController
    @StateObject private var wakeTaskReconfirmation: WakeTaskReconfirmationController
    private let launchesForBackgroundScheduling: Bool

    init() {
        if CommandLine.arguments.contains(ZC052005AcceptanceProbe.argument) {
            let exitCode = ZC052005AcceptanceProbe.run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        if CommandLine.arguments.contains(ReminderCompletionSyncXPCProbe.argument) {
            let exitCode = ReminderCompletionSyncXPCProbe.run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        if CommandLine.arguments.contains(ManualLocalTaskXPCProbe.argument) {
            let exitCode = ManualLocalTaskXPCProbe.run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.registerAgentArgument) {
            let exitCode = PolicyMutationXPCProbe.registerAgent()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.unregisterAgentArgument) {
            let exitCode = PolicyMutationXPCProbe.unregisterAgent()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.argument) {
            let exitCode = PolicyMutationXPCProbe.run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        let isBackgroundLaunch = CommandLine.arguments.contains("--background-schedule")
        launchesForBackgroundScheduling = isBackgroundLaunch
        _model = StateObject(wrappedValue: AppModel())
        _voiceModel = StateObject(wrappedValue: VoiceConversationModel())
        _onboarding = StateObject(wrappedValue: OnboardingCoordinator())
        _agentLifecycle = StateObject(wrappedValue: AgentLifecycleController())
        _wakeTaskReconfirmation = StateObject(wrappedValue: WakeTaskReconfirmationController())
    }

    var body: some Scene {
        WindowGroup("Zoid 666", id: "main") {
            Group {
                if onboarding.route == .onboarding {
                    OnboardingRootView(coordinator: onboarding)
                } else {
                    VStack(spacing: 0) {
                        if !onboarding.progress.isFinished {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SETUP IS PAUSED")
                                        .font(Sumi.label(9))
                                        .sumiLabelTracking()
                                    Text("Resume from \(onboarding.progress.currentStep.rawValue) when you are ready.")
                                        .font(Sumi.body(12))
                                        .foregroundStyle(Sumi.muted)
                                }
                                Spacer()
                                Button("RESUME SETUP") { onboarding.resumeSetup() }
                                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                                    .accessibilityIdentifier("today.resume-setup")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Sumi.softPaper)
                            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("today.setup-paused")
                        }
                        DashboardView()
                    }
                }
            }
                .environmentObject(model)
                .environmentObject(voiceModel)
                .frame(minWidth: 980, minHeight: 680)
                .background(Sumi.paper)
                .overlay(alignment: .topTrailing) {
                    if let notice = wakeTaskReconfirmation.notice {
                        WakeTaskReconciliationNoticeView(
                            notice: notice,
                            dismiss: { wakeTaskReconfirmation.dismissNotice() }
                        )
                        .padding(20)
                    }
                }
                .sheet(item: Binding(
                    get: { wakeTaskReconfirmation.pendingConfirmation },
                    set: { _ in }
                )) { confirmation in
                    WakeTaskReconfirmationView(
                        confirmation: confirmation,
                        continueTask: {
                            wakeTaskReconfirmation.confirmTaskIsStillActive()
                        },
                        pauseTask: {
                            model.applyTaskCommand(.pauseForExternalInterruption, taskID: confirmation.taskID)
                            wakeTaskReconfirmation.confirmTaskWasInterrupted()
                        }
                    )
                    .interactiveDismissDisabled()
                }
                .onAppear {
                    if onboarding.route == .today {
                        voiceModel.startAlwaysAvailable()
                    }
                    positionInitialWindow()
                    if launchesForBackgroundScheduling {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            NSApp.hide(nil)
                        }
                    }
                }
                .onChange(of: onboarding.route) { _, route in
                    if route == .today {
                        voiceModel.startAlwaysAvailable()
                        Task {
                            await model.refreshTodaySnapshot()
                            await model.refreshPromptInbox()
                            await model.refreshActionAudit()
                        }
                    }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    wakeTaskReconfirmation.noteInactive()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
                    wakeTaskReconfirmation.noteInactive()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    reconcileTaskAfterWake()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
                    reconcileTaskAfterWake()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        if onboarding.route == .onboarding,
                           onboarding.progress.currentStep == .deliveryTest {
                            await onboarding.restoreTestPrompt()
                        }
                        await model.refreshPromptInbox()
                        await model.refreshActionAudit()
                        await model.refreshRuntimeSafety()
                        await model.refreshCaptureHealth()
                        model.reloadMeetingCandidatesForForegroundActivation()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
            TaskKeyboardCommands(model: model, isAvailable: onboarding.route == .today)
            AgentLifecycleCommands()
        }

        Window("Background Agent", id: "agent-lifecycle") {
            AgentLifecycleView(controller: agentLifecycle)
        }
        .defaultSize(width: 760, height: 660)

        MenuBarExtra {
            MenuBarCoachView(appModel: model, voiceModel: voiceModel)
        } label: {
            Image(systemName: menuBarState.menuBarSymbol)
                .accessibilityLabel(menuBarState.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarState: MenuBarCoachState {
        MenuBarCoachState(
            snapshot: model.todaySnapshot,
            unresolvedPromptCount: model.promptEpisodes.count,
            notificationsUnavailable: notificationsUnavailable
        )
    }

    private var notificationsUnavailable: Bool {
        guard let notifications = model.sources.first(where: { $0.id == .notifications }) else {
            return false
        }
        return notifications.state == .attention
            || notifications.state == .notConnected
            || notifications.state == .unavailable
    }

    private func positionInitialWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.canBecomeKey && $0.level == .normal
            }) else { return }

            let frameAutosaveName = "ZoidCoachMainWindowFrame"
            if !window.setFrameUsingName(frameAutosaveName) {
                window.setContentSize(NSSize(width: 1180, height: 760))
                window.center()
            }
            window.setFrameAutosaveName(frameAutosaveName)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func reconcileTaskAfterWake() {
        guard onboarding.route == .today else { return }
        Task {
            await model.refreshTodaySnapshot()
            let activeTaskID = model.todaySnapshot?.activeTask?.taskID
            let activeTaskTitle = model.todaySnapshot?.taskRows.first(where: {
                $0.taskID == activeTaskID
            })?.title
            wakeTaskReconfirmation.reconcileActivation(
                activeTaskID: activeTaskID,
                taskTitle: activeTaskTitle
            )
        }
    }
}
