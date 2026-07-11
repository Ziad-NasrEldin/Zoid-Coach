import AppKit
import SwiftUI

@main
struct ZoidCoachApplication: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var voiceModel: VoiceConversationModel
    private let launchesForBackgroundScheduling: Bool

    init() {
        let isBackgroundLaunch = CommandLine.arguments.contains("--background-schedule")
        launchesForBackgroundScheduling = isBackgroundLaunch
        _model = StateObject(wrappedValue: AppModel())
        _voiceModel = StateObject(wrappedValue: VoiceConversationModel())
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .environmentObject(voiceModel)
                .frame(minWidth: 980, minHeight: 680)
                .background(Sumi.paper)
                .onAppear {
                    voiceModel.startAlwaysAvailable()
                    positionInitialWindow()
                    if launchesForBackgroundScheduling {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            NSApp.hide(nil)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.refreshPromptInbox()
                        model.reloadMeetingCandidatesForForegroundActivation()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("Zoid Voice", systemImage: voiceMenuSymbol) {
            VoiceMenuView(model: voiceModel)
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

    private var voiceMenuSymbol: String {
        switch voiceModel.state {
        case .listening: "mic.fill"
        case .speaking: "waveform.circle.fill"
        case .thinking, .activating: "ellipsis.circle.fill"
        case .localFallback: "mic.badge.xmark"
        case .idle, .disconnected: "waveform.circle"
        }
    }
}
