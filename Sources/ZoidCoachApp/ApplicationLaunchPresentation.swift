import AppKit
import SwiftUI
import ZoidCoachCore

struct ApplicationLaunchPresentation: Equatable {
    static let qaOpenMainWindowArgument = "--qa-open-main"
    static let backgroundScheduleArgument = "--background-schedule"

    let launchesForBackgroundScheduling: Bool
    let shouldOpenMainWindow: Bool

    var initialMainWindowPresentationPolicy: InitialMainWindowPresentationPolicy {
        launchesForBackgroundScheduling ? .backgroundScheduling : .ordinary
    }

    init(arguments: [String], packageMode: RuntimePackageMode?) {
        launchesForBackgroundScheduling = arguments.contains(Self.backgroundScheduleArgument)
        shouldOpenMainWindow = packageMode == .qa
            && arguments.contains(Self.qaOpenMainWindowArgument)
            && !launchesForBackgroundScheduling
    }
}

enum InitialMainWindowPresentationPolicy: Equatable {
    case ordinary
    case backgroundScheduling
}

@MainActor
final class BackgroundApplicationLifecycleHook {
    let policy: InitialMainWindowPresentationPolicy
    let isAccessoryActivationPolicySet: () -> Bool
    let setAccessoryActivationPolicy: () -> Void
    let acquireAutomaticTerminationHold: () -> Void
    let releaseAutomaticTerminationHold: () -> Void
    let availableWindows: () -> [ApplicationWindowDescriptor]
    let dismissWindow: (Int) -> Void
    private var didRequestAccessoryActivation = false
    private var holdsAutomaticTermination = false
    private var isDismissingWindows = false

    init(
        policy: InitialMainWindowPresentationPolicy,
        isAccessoryActivationPolicySet: @escaping () -> Bool = { false },
        setAccessoryActivationPolicy: @escaping () -> Void,
        acquireAutomaticTerminationHold: @escaping () -> Void = {},
        releaseAutomaticTerminationHold: @escaping () -> Void = {},
        availableWindows: @escaping () -> [ApplicationWindowDescriptor],
        dismissWindow: @escaping (Int) -> Void
    ) {
        self.policy = policy
        self.isAccessoryActivationPolicySet = isAccessoryActivationPolicySet
        self.setAccessoryActivationPolicy = setAccessoryActivationPolicy
        self.acquireAutomaticTerminationHold = acquireAutomaticTerminationHold
        self.releaseAutomaticTerminationHold = releaseAutomaticTerminationHold
        self.availableWindows = availableWindows
        self.dismissWindow = dismissWindow
    }

    var shouldObserveWindowVisibility: Bool {
        policy == .backgroundScheduling
    }

    func applicationWillFinishLaunching() {
        guard policy == .backgroundScheduling else { return }
        applyBackgroundLifetimePolicy()
        dismissVisibleNormalWindows()
    }

    func applicationDidFinishLaunching() {
        guard policy == .backgroundScheduling else { return }
        applyBackgroundLifetimePolicy()
        dismissVisibleNormalWindows()
    }

    func applicationDidUpdate() {
        guard policy == .backgroundScheduling else { return }
        applyBackgroundLifetimePolicy()
        dismissVisibleNormalWindows()
    }

    func applicationWillTerminate() {
        guard policy == .backgroundScheduling, holdsAutomaticTermination else { return }
        holdsAutomaticTermination = false
        releaseAutomaticTerminationHold()
    }

    func windowDidBecomeVisible(_ window: ApplicationWindowDescriptor) {
        guard policy == .backgroundScheduling,
              window.isVisible,
              window.isNormalLevel
        else {
            return
        }
        dismissWindow(window.windowNumber)
    }

    func shouldTerminateAfterLastWindowClosed(defaultDecision: Bool) -> Bool {
        policy == .backgroundScheduling ? false : defaultDecision
    }

    private func applyBackgroundLifetimePolicy() {
        if !didRequestAccessoryActivation {
            didRequestAccessoryActivation = true
            if !isAccessoryActivationPolicySet() {
                setAccessoryActivationPolicy()
            }
        }
        if !holdsAutomaticTermination {
            acquireAutomaticTerminationHold()
            holdsAutomaticTermination = true
        }
    }

    private func dismissVisibleNormalWindows() {
        guard !isDismissingWindows else { return }
        isDismissingWindows = true
        defer { isDismissingWindows = false }
        for window in availableWindows() where window.isVisible && window.isNormalLevel {
            dismissWindow(window.windowNumber)
        }
    }
}

struct ApplicationWindowDescriptor: Equatable, Sendable {
    let windowNumber: Int
    let identifier: String?
    let title: String
    let canBecomeKey: Bool
    let isVisible: Bool
    let isNormalLevel: Bool

    @MainActor
    init(window: NSWindow) {
        windowNumber = window.windowNumber
        identifier = window.identifier?.rawValue
        title = window.title
        canBecomeKey = window.canBecomeKey
        isVisible = window.isVisible
        isNormalLevel = window.level == .normal
    }

    init(
        windowNumber: Int,
        identifier: String?,
        title: String,
        canBecomeKey: Bool,
        isVisible: Bool = true,
        isNormalLevel: Bool
    ) {
        self.windowNumber = windowNumber
        self.identifier = identifier
        self.title = title
        self.canBecomeKey = canBecomeKey
        self.isVisible = isVisible
        self.isNormalLevel = isNormalLevel
    }
}

enum MainApplicationWindowSelector {
    static let mainWindowIdentifier = "zoid-666.main-window"
    static let mainWindowTitle = "Zoid 666"
    static let backgroundAgentWindowTitle = "Background Agent"

    static func select(from windows: [ApplicationWindowDescriptor]) -> ApplicationWindowDescriptor? {
        let eligible = windows.filter {
            $0.canBecomeKey
                && $0.isNormalLevel
                && $0.title != backgroundAgentWindowTitle
        }
        return eligible.first { $0.identifier == mainWindowIdentifier }
            ?? eligible.first { $0.title == mainWindowTitle }
    }
}

@MainActor
struct InitialMainWindowPresentationCoordinator {
    let availableWindows: () -> [ApplicationWindowDescriptor]
    let positionWindow: (Int) -> Void
    let dismissWindow: (Int) -> Void
    let schedulePosition: (@escaping @MainActor () -> Void) -> Void

    func apply(policy: InitialMainWindowPresentationPolicy) {
        switch policy {
        case .ordinary:
            schedulePosition {
                guard let mainWindow = MainApplicationWindowSelector.select(
                    from: self.availableWindows()
                ) else {
                    return
                }
                self.positionWindow(mainWindow.windowNumber)
            }
        case .backgroundScheduling:
            for window in availableWindows() where window.isNormalLevel {
                dismissWindow(window.windowNumber)
            }
        }
    }
}

@MainActor
struct QAMainWindowOpeningCoordinator {
    let requestMainWindow: () -> Void
    let activateApplication: () -> Void
    let availableWindows: () -> [ApplicationWindowDescriptor]
    let foregroundWindow: (Int) -> Void
    let scheduleRetry: (@escaping @MainActor () -> Void) -> Void
    let maximumForegroundAttempts: Int

    init(
        requestMainWindow: @escaping () -> Void,
        activateApplication: @escaping () -> Void,
        availableWindows: @escaping () -> [ApplicationWindowDescriptor],
        foregroundWindow: @escaping (Int) -> Void,
        scheduleRetry: @escaping (@escaping @MainActor () -> Void) -> Void,
        maximumForegroundAttempts: Int = 20
    ) {
        self.requestMainWindow = requestMainWindow
        self.activateApplication = activateApplication
        self.availableWindows = availableWindows
        self.foregroundWindow = foregroundWindow
        self.scheduleRetry = scheduleRetry
        self.maximumForegroundAttempts = max(1, maximumForegroundAttempts)
    }

    func open() {
        requestMainWindow()
        activateApplication()
        foregroundMainWindow(attempt: 1)
    }

    private func foregroundMainWindow(attempt: Int) {
        if let mainWindow = MainApplicationWindowSelector.select(from: availableWindows()) {
            foregroundWindow(mainWindow.windowNumber)
            return
        }
        guard attempt < maximumForegroundAttempts else { return }
        scheduleRetry {
            foregroundMainWindow(attempt: attempt + 1)
        }
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
                    availableWindows: {
                        NSApplication.shared.windows.map(ApplicationWindowDescriptor.init)
                    },
                    foregroundWindow: { windowNumber in
                        NSApplication.shared.windows
                            .first(where: { $0.windowNumber == windowNumber })?
                            .makeKeyAndOrderFront(nil)
                    },
                    scheduleRetry: { action in
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 0.05,
                            execute: action
                        )
                    }
                )
            )
        }
    }
}

struct MainApplicationWindowIdentityInstaller: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        MainApplicationWindowIdentityView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? MainApplicationWindowIdentityView)?.applyIdentity()
    }
}

private final class MainApplicationWindowIdentityView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIdentity()
    }

    func applyIdentity() {
        window?.identifier = NSUserInterfaceItemIdentifier(
            MainApplicationWindowSelector.mainWindowIdentifier
        )
    }
}
