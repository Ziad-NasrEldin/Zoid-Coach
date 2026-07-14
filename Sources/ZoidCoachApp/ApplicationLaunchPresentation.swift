import AppKit
import SwiftUI
import ZoidCoachCore

struct ApplicationLaunchPresentation: Equatable {
    static let qaOpenMainWindowArgument = "--qa-open-main"
    static let backgroundScheduleArgument = "--background-schedule"

    let launchesForBackgroundScheduling: Bool
    let shouldOpenMainWindow: Bool

    init(arguments: [String], packageMode: RuntimePackageMode?) {
        launchesForBackgroundScheduling = arguments.contains(Self.backgroundScheduleArgument)
        shouldOpenMainWindow = packageMode == .qa
            && arguments.contains(Self.qaOpenMainWindowArgument)
            && !launchesForBackgroundScheduling
    }
}

@MainActor
struct QAMainWindowOpeningCoordinator {
    let requestMainWindow: () -> Void
    let activateApplication: () -> Void
    let foregroundMainWindow: () -> Void
    let deferForeground: (@escaping () -> Void) -> Void

    func open() {
        requestMainWindow()
        activateApplication()
        deferForeground(foregroundMainWindow)
    }
}

@MainActor
struct QAMainWindowLaunchGate {
    private(set) var hasOpenedMainWindow = false

    mutating func openIfNeeded(
        shouldOpenMainWindow: Bool,
        coordinator: QAMainWindowOpeningCoordinator
    ) {
        guard shouldOpenMainWindow, !hasOpenedMainWindow else { return }
        hasOpenedMainWindow = true
        coordinator.open()
    }
}

struct QAMainWindowLaunchModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @State private var gate = QAMainWindowLaunchGate()

    let shouldOpenMainWindow: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            gate.openIfNeeded(
                shouldOpenMainWindow: shouldOpenMainWindow,
                coordinator: QAMainWindowOpeningCoordinator(
                    requestMainWindow: { openWindow(id: "main") },
                    activateApplication: {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    },
                    foregroundMainWindow: {
                        NSApplication.shared.windows
                            .first(where: { $0.canBecomeKey && $0.level == .normal })?
                            .makeKeyAndOrderFront(nil)
                    },
                    deferForeground: { action in
                        DispatchQueue.main.async(execute: action)
                    }
                )
            )
        }
    }
}
