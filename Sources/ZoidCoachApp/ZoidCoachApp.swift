import AppKit
import Darwin
import SwiftUI
import ZoidCoachCore

@MainActor
final class ZoidCoachApplicationDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleHook: BackgroundApplicationLifecycleHook

    override init() {
        let runtimeEnvironment = RuntimeEnvironment.current()
        let launchPresentation = ApplicationLaunchPresentation(
            arguments: CommandLine.arguments,
            packageMode: runtimeEnvironment.packageMode
        )
        lifecycleHook = BackgroundApplicationLifecycleHook(
            policy: launchPresentation.initialMainWindowPresentationPolicy,
            setAccessoryActivationPolicy: {
                NSApplication.shared.setActivationPolicy(.accessory)
            },
            availableWindows: {
                NSApplication.shared.windows.map(ApplicationWindowDescriptor.init)
            },
            dismissWindow: { windowNumber in
                NSApplication.shared.windows
                    .first(where: { $0.windowNumber == windowNumber })?
                    .orderOut(nil)
            }
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        lifecycleHook.applicationWillFinishLaunching()
        guard lifecycleHook.shouldObserveWindowVisibility else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleHook.applicationDidFinishLaunching()
    }

    func applicationDidUpdate(_ notification: Notification) {
        lifecycleHook.applicationDidUpdate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleHook.shouldTerminateAfterLastWindowClosed(defaultDecision: false)
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        lifecycleHook.windowDidBecomeVisible(ApplicationWindowDescriptor(window: window))
    }
}

@main
struct ZoidCoachApplication: App {
    @NSApplicationDelegateAdaptor(ZoidCoachApplicationDelegate.self)
    private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var voiceModel: VoiceConversationModel
    @StateObject private var onboarding: OnboardingCoordinator
    @StateObject private var agentLifecycle: AgentLifecycleController
    @StateObject private var wakeTaskReconfirmation: WakeTaskReconfirmationController
    @StateObject private var menuBarCoach: MenuBarCoachController
    @StateObject private var menuBarCoachingPause: MenuBarCoachingPauseController
    private let initialMainWindowPresentationPolicy: InitialMainWindowPresentationPolicy
    private let shouldOpenMainWindow: Bool

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
        let runtimeEnvironment = RuntimeEnvironment.current()
        let launchPresentation = ApplicationLaunchPresentation(
            arguments: CommandLine.arguments,
            packageMode: runtimeEnvironment.packageMode
        )
        initialMainWindowPresentationPolicy = launchPresentation.initialMainWindowPresentationPolicy
        shouldOpenMainWindow = launchPresentation.shouldOpenMainWindow
        _model = StateObject(wrappedValue: AppModel(runtimeEnvironment: runtimeEnvironment))
        _voiceModel = StateObject(wrappedValue: VoiceConversationModel())
        _onboarding = StateObject(wrappedValue: OnboardingCoordinator())
        _agentLifecycle = StateObject(wrappedValue: AgentLifecycleController())
        _wakeTaskReconfirmation = StateObject(wrappedValue: WakeTaskReconfirmationController())
        _menuBarCoach = StateObject(wrappedValue: MenuBarCoachController(
            runtimeEnvironment: runtimeEnvironment
        ))
        _menuBarCoachingPause = StateObject(wrappedValue: MenuBarCoachingPauseController(
            runtimeEnvironment: runtimeEnvironment
        ))
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
                .background(MainApplicationWindowIdentityInstaller())
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
                    presentInitialMainWindow()
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
            DailyReviewNavigationCommands(model: model, isAvailable: onboarding.route == .today)
            AgentLifecycleCommands()
        }

        Window("Background Agent", id: "agent-lifecycle") {
            AgentLifecycleView(controller: agentLifecycle)
        }
        .defaultSize(width: 760, height: 660)

        MenuBarExtra {
            MenuBarCoachView(
                appModel: model,
                voiceModel: voiceModel,
                controller: menuBarCoach,
                pauseController: menuBarCoachingPause
            )
        } label: {
            Image(systemName: menuBarState.menuBarSymbol)
                .accessibilityLabel(menuBarState.menuBarLabel)
                .modifier(QAMainWindowLaunchModifier(
                    shouldOpenMainWindow: shouldOpenMainWindow
                ))
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

    private func presentInitialMainWindow() {
        InitialMainWindowPresentationCoordinator(
            availableWindows: {
                NSApplication.shared.windows.map(ApplicationWindowDescriptor.init)
            },
            positionWindow: { windowNumber in
                guard let window = NSApplication.shared.windows.first(where: {
                    $0.windowNumber == windowNumber
                }) else {
                    return
                }
                let frameAutosaveName = "ZoidCoachMainWindowFrame"
                if !window.setFrameUsingName(frameAutosaveName) {
                    window.setContentSize(NSSize(width: 1180, height: 760))
                    window.center()
                }
                window.setFrameAutosaveName(frameAutosaveName)
                window.makeKeyAndOrderFront(nil)
            },
            dismissWindow: { windowNumber in
                NSApplication.shared.windows
                    .first(where: { $0.windowNumber == windowNumber })?
                    .orderOut(nil)
            },
            schedulePosition: { action in
                DispatchQueue.main.async(execute: action)
            }
        ).apply(policy: initialMainWindowPresentationPolicy)
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
