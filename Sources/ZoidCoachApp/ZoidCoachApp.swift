import AppKit
import Darwin
import OSLog
import SwiftUI
import ZoidCoachCore

struct TodayLiveRefreshEligibility: Equatable {
    let onboardingIsReady: Bool
    let todayIsSelected: Bool
    let sceneIsActive: Bool
    let applicationIsActive: Bool

    var isEnabled: Bool {
        onboardingIsReady && todayIsSelected && sceneIsActive && applicationIsActive
    }
}

@MainActor
final class ApplicationActivationMonitor: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool

    private let notificationCenter: NotificationCenter
    private let onTransition: ((Bool) -> Void)?

    init(
        notificationCenter: NotificationCenter = .default,
        initiallyActive: Bool = NSApplication.shared.isActive,
        onTransition: ((Bool) -> Void)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.isActive = initiallyActive
        self.onTransition = onTransition
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        setActive(true)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        setActive(false)
    }

    private func setActive(_ newValue: Bool) {
        guard isActive != newValue else { return }
        isActive = newValue
        onTransition?(newValue)
    }
}

@MainActor
private struct ZoidCoachApplicationLaunchContext {
    let runtimeEnvironment: RuntimeEnvironment
    let launchPresentation: ApplicationLaunchPresentation
    let entrypointSelection: ApplicationEntrypointSelection

    init() {
        let runtimeEnvironment = RuntimeEnvironment.current()
        self.runtimeEnvironment = runtimeEnvironment
        launchPresentation = ApplicationLaunchPresentation(
            arguments: CommandLine.arguments,
            packageMode: runtimeEnvironment.packageMode
        )
        entrypointSelection = ApplicationEntrypointSelection.select(
            arguments: CommandLine.arguments,
            packageMode: runtimeEnvironment.packageMode
        )
    }
}

@MainActor
private final class ZoidCoachApplicationDependencies {
    let model: AppModel
    let voiceModel: VoiceConversationModel
    let onboarding: OnboardingCoordinator
    let agentLifecycle: AgentLifecycleController
    let wakeTaskReconfirmation: WakeTaskReconfirmationController
    let menuBarCoach: MenuBarCoachController
    let menuBarCoachingPause: MenuBarCoachingPauseController

    init(runtimeEnvironment: RuntimeEnvironment) {
        model = AppModel(runtimeEnvironment: runtimeEnvironment)
        voiceModel = VoiceConversationModel()
        onboarding = OnboardingCoordinator()
        agentLifecycle = AgentLifecycleController()
        wakeTaskReconfirmation = WakeTaskReconfirmationController()
        menuBarCoach = MenuBarCoachController(runtimeEnvironment: runtimeEnvironment)
        menuBarCoachingPause = MenuBarCoachingPauseController(
            runtimeEnvironment: runtimeEnvironment
        )
    }
}

@MainActor
private enum ZoidCoachApplicationBootstrap {
    static let context = ZoidCoachApplicationLaunchContext()
    static let dependencies = ZoidCoachApplicationDependencies(
        runtimeEnvironment: context.runtimeEnvironment
    )
}

@main
enum ZoidCoachApplicationEntrypoint {
    @MainActor
    static func main() {
        if let exitCode = acceptanceProbeExitCode() {
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }

        switch ZoidCoachApplicationBootstrap.context.entrypointSelection {
        case .foreground:
            ZoidCoachForegroundApplication.main()
        case .background:
            ZoidCoachBackgroundApplication.main()
        }
    }

    @MainActor
    private static func acceptanceProbeExitCode() -> Int32? {
        if CommandLine.arguments.contains(ZC052005AcceptanceProbe.argument) {
            return ZC052005AcceptanceProbe.run()
        }
        if CommandLine.arguments.contains(ReminderCompletionSyncXPCProbe.argument) {
            return ReminderCompletionSyncXPCProbe.run()
        }
        if CommandLine.arguments.contains(ManualLocalTaskXPCProbe.argument) {
            return ManualLocalTaskXPCProbe.run()
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.registerAgentArgument) {
            return PolicyMutationXPCProbe.registerAgent()
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.unregisterAgentArgument) {
            return PolicyMutationXPCProbe.unregisterAgent()
        }
        if CommandLine.arguments.contains(PolicyMutationXPCProbe.argument) {
            return PolicyMutationXPCProbe.run()
        }
        return nil
    }
}

@MainActor
final class ZoidCoachApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let automaticTerminationReason = "Zoid 666 background scheduling menu"
    private static let lifecycleLogger = Logger(
        subsystem: "com.zoidcoach.app",
        category: "background-lifecycle"
    )
    private let lifecycleHook: BackgroundApplicationLifecycleHook

    override init() {
        let launchPresentation = ZoidCoachApplicationBootstrap.context.launchPresentation
        lifecycleHook = BackgroundApplicationLifecycleHook(
            policy: launchPresentation.initialMainWindowPresentationPolicy,
            isAccessoryActivationPolicySet: {
                NSApplication.shared.activationPolicy() == .accessory
            },
            setAccessoryActivationPolicy: {
                NSApplication.shared.setActivationPolicy(.accessory)
            },
            acquireAutomaticTerminationHold: {
                Self.lifecycleLogger.notice(
                    "lifecycle-hold action=acquire policy=background-scheduling"
                )
                ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
            },
            releaseAutomaticTerminationHold: {
                Self.lifecycleLogger.notice(
                    "lifecycle-hold action=release policy=background-scheduling"
                )
                ProcessInfo.processInfo.enableAutomaticTermination(Self.automaticTerminationReason)
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
        Self.lifecycleLogger.notice(
            "delegate-init policy=\(self.lifecycleHook.policy.logLabel, privacy: .public)"
        )
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

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleHook.applicationWillTerminate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let decision = lifecycleHook.applicationTerminationDecision()
        Self.lifecycleLogger.notice(
            "termination-decision policy=\(self.lifecycleHook.policy.logLabel, privacy: .public) decision=\(decision.logLabel, privacy: .public)"
        )
        switch decision {
        case .cancel:
            return .terminateCancel
        case .permit:
            return .terminateNow
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleHook.shouldTerminateAfterLastWindowClosed(defaultDecision: false)
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        lifecycleHook.windowDidBecomeVisible(ApplicationWindowDescriptor(window: window))
    }
}

struct ZoidCoachBackgroundApplication: App {
    @NSApplicationDelegateAdaptor(ZoidCoachApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var model: AppModel
    @StateObject private var voiceModel: VoiceConversationModel
    @StateObject private var menuBarCoach: MenuBarCoachController
    @StateObject private var menuBarCoachingPause: MenuBarCoachingPauseController

    init() {
        let dependencies = ZoidCoachApplicationBootstrap.dependencies
        _model = StateObject(wrappedValue: dependencies.model)
        _voiceModel = StateObject(wrappedValue: dependencies.voiceModel)
        _menuBarCoach = StateObject(wrappedValue: dependencies.menuBarCoach)
        _menuBarCoachingPause = StateObject(wrappedValue: dependencies.menuBarCoachingPause)
    }

    var body: some Scene {
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
}

struct ZoidCoachForegroundApplication: App {
    @NSApplicationDelegateAdaptor(ZoidCoachApplicationDelegate.self)
    private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var applicationActivation: ApplicationActivationMonitor
    @StateObject private var voiceModel: VoiceConversationModel
    @StateObject private var onboarding: OnboardingCoordinator
    @StateObject private var agentLifecycle: AgentLifecycleController
    @StateObject private var wakeTaskReconfirmation: WakeTaskReconfirmationController
    @StateObject private var menuBarCoach: MenuBarCoachController
    @StateObject private var menuBarCoachingPause: MenuBarCoachingPauseController
    private let initialMainWindowPresentationPolicy: InitialMainWindowPresentationPolicy
    private let sceneCompositionPolicy: ApplicationSceneCompositionPolicy
    private let shouldOpenMainWindow: Bool

    init() {
        let context = ZoidCoachApplicationBootstrap.context
        let dependencies = ZoidCoachApplicationBootstrap.dependencies
        let launchPresentation = context.launchPresentation
        initialMainWindowPresentationPolicy = launchPresentation.initialMainWindowPresentationPolicy
        sceneCompositionPolicy = launchPresentation.sceneCompositionPolicy
        shouldOpenMainWindow = launchPresentation.shouldOpenMainWindow
        _model = StateObject(wrappedValue: AppModel(runtimeEnvironment: runtimeEnvironment))
        _applicationActivation = StateObject(wrappedValue: ApplicationActivationMonitor())
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
        if sceneCompositionPolicy.includesMainWindowScene {
            mainWindowScene
        }
        if sceneCompositionPolicy.includesAgentWindowScene {
            agentWindowScene
        }
        if sceneCompositionPolicy.includesMenuBarScene {
            menuBarScene
        }
    }

    private var mainWindowScene: some Scene {
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
                    updateTodayLiveRefresh()
                    presentInitialMainWindow()
                }
                .onChange(of: onboarding.route) { _, route in
                    updateTodayLiveRefresh()
                    if route == .today {
                        voiceModel.startAlwaysAvailable()
                        Task {
                            await model.refreshTodaySnapshot()
                            await model.refreshPromptInbox()
                            await model.refreshActionAudit()
                        }
                    }
                }
                .onChange(of: model.selectedSection) { _, _ in
                    updateTodayLiveRefresh()
                }
                .onChange(of: applicationActivation.isActive) { _, _ in
                    updateTodayLiveRefresh()
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
                    updateTodayLiveRefresh()
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
    }

    private var agentWindowScene: some Scene {
        Window("Background Agent", id: "agent-lifecycle") {
            AgentLifecycleView(controller: agentLifecycle)
        }
        .defaultSize(width: 760, height: 660)
    }

    private var menuBarScene: some Scene {
        MenuBarExtra {
            MenuBarCoachView(
                appModel: model,
                voiceModel: voiceModel,
                controller: menuBarCoach,
                pauseController: menuBarCoachingPause
            )
        } label: {
            Label("Zoid 666", systemImage: menuBarState.menuBarSymbol)
                .labelStyle(.iconOnly)
                .accessibilityLabel(menuBarState.menuBarLabel)
                .accessibilityValue(menuBarState.menuBarLabel)
                .accessibilityIdentifier("menu-bar.status-item")
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

    private func updateTodayLiveRefresh() {
        let eligibility = TodayLiveRefreshEligibility(
            onboardingIsReady: onboarding.route == .today,
            todayIsSelected: model.selectedSection == .today,
            sceneIsActive: scenePhase == .active,
            applicationIsActive: applicationActivation.isActive
        )
        model.setTodayLiveRefreshEnabled(eligibility.isEnabled)
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

    private func dismissInitialWindowsForBackgroundScheduling() {
        for window in NSApp.windows where window.level == .normal {
            window.orderOut(nil)
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
