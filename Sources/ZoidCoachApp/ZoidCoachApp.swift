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
    private let launchesForBackgroundScheduling: Bool

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
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
            AgentLifecycleCommands()
        }

        Window("Background Agent", id: "agent-lifecycle") {
            AgentLifecycleView(controller: agentLifecycle)
        }
        .defaultSize(width: 760, height: 660)

        MenuBarExtra("Zoid 666", systemImage: MenuBarCoachState(snapshot: model.todaySnapshot).tone.symbol) {
            MenuBarCoachView(appModel: model, voiceModel: voiceModel)
        }
        .menuBarExtraStyle(.window)
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
}
