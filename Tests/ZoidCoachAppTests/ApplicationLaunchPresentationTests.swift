import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test func packagedQAOpenMainArgumentRequestsThePrimaryWindow() {
    let presentation = ApplicationLaunchPresentation(
        arguments: ["ZoidCoachQA", "--qa-open-main"],
        packageMode: .qa
    )

    #expect(presentation.shouldOpenMainWindow)
    #expect(!presentation.launchesForBackgroundScheduling)
}

@Test func productionPackageIgnoresTheQAOpenMainArgument() {
    let presentation = ApplicationLaunchPresentation(
        arguments: ["ZoidCoach", "--qa-open-main"],
        packageMode: .production
    )

    #expect(!presentation.shouldOpenMainWindow)
    #expect(!presentation.launchesForBackgroundScheduling)
}

@Test func backgroundSchedulingNeverOpensThePrimaryWindow() {
    let presentation = ApplicationLaunchPresentation(
        arguments: ["ZoidCoachQA", "--background-schedule", "--qa-open-main"],
        packageMode: .qa
    )

    #expect(presentation.launchesForBackgroundScheduling)
    #expect(!presentation.shouldOpenMainWindow)
    #expect(presentation.initialMainWindowPresentationPolicy == .backgroundScheduling)
}

@Test func ordinaryQALaunchKeepsNormalSceneRestoration() {
    let presentation = ApplicationLaunchPresentation(
        arguments: ["ZoidCoachQA"],
        packageMode: .qa
    )

    #expect(!presentation.shouldOpenMainWindow)
    #expect(!presentation.launchesForBackgroundScheduling)
}

@Test func mainWindowSelectionExcludesBackgroundAgentWhenBothWindowsExist() throws {
    let selected = try #require(MainApplicationWindowSelector.select(from: [
        ApplicationWindowDescriptor(
            windowNumber: 41,
            identifier: "agent-lifecycle",
            title: "Background Agent",
            canBecomeKey: true,
            isNormalLevel: true
        ),
        ApplicationWindowDescriptor(
            windowNumber: 42,
            identifier: MainApplicationWindowSelector.mainWindowIdentifier,
            title: "Zoid 666",
            canBecomeKey: true,
            isNormalLevel: true
        ),
    ]))

    #expect(selected.windowNumber == 42)
    #expect(selected.title == "Zoid 666")
}

@MainActor
@Test func qaMainWindowLaunchIsForegroundedExactlyOnce() {
    var events: [String] = []
    let backgroundWindow = applicationWindow(
        number: 41,
        identifier: "agent-lifecycle",
        title: "Background Agent"
    )
    let mainWindow = applicationWindow(
        number: 42,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    let coordinator = QAMainWindowOpeningCoordinator(
        requestMainWindow: { events.append("request-main") },
        activateApplication: { events.append("activate") },
        availableWindows: { [backgroundWindow, mainWindow] },
        foregroundWindow: { events.append("foreground-\($0)") },
        scheduleRetry: { action in
            events.append("retry")
            action()
        }
    )
    var gate = QAMainWindowLaunchGate()

    gate.openIfNeeded(shouldOpenMainWindow: false, coordinator: coordinator)
    gate.openIfNeeded(shouldOpenMainWindow: true, coordinator: coordinator)
    gate.openIfNeeded(shouldOpenMainWindow: true, coordinator: coordinator)

    #expect(events == ["request-main", "activate", "foreground-42"])
    #expect(gate.hasOpenedMainWindow)
}

@MainActor
@Test func backgroundSchedulingSuppressesOpeningForegroundingAndPositioning() {
    let presentation = ApplicationLaunchPresentation(
        arguments: ["ZoidCoachQA", "--background-schedule", "--qa-open-main"],
        packageMode: .qa
    )
    var events: [String] = []
    let backgroundWindow = applicationWindow(
        number: 41,
        identifier: "agent-lifecycle",
        title: "Background Agent"
    )
    let mainWindow = applicationWindow(
        number: 42,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    let openingCoordinator = QAMainWindowOpeningCoordinator(
        requestMainWindow: { events.append("request-main") },
        activateApplication: { events.append("activate") },
        availableWindows: { [backgroundWindow, mainWindow] },
        foregroundWindow: { events.append("foreground-\($0)") },
        scheduleRetry: { _ in events.append("retry") }
    )
    let presentationCoordinator = InitialMainWindowPresentationCoordinator(
        availableWindows: { [backgroundWindow, mainWindow] },
        positionWindow: { events.append("position-\($0)") },
        dismissWindow: { events.append("dismiss-\($0)") },
        schedulePosition: { _ in events.append("schedule-position") }
    )
    var gate = QAMainWindowLaunchGate()

    gate.openIfNeeded(
        shouldOpenMainWindow: presentation.shouldOpenMainWindow,
        coordinator: openingCoordinator
    )
    presentationCoordinator.apply(policy: presentation.initialMainWindowPresentationPolicy)

    #expect(events == ["dismiss-41", "dismiss-42"])
    #expect(!gate.hasOpenedMainWindow)
}

@MainActor
@Test func ordinaryLaunchPositionsOnlyTheSelectedMainWindow() {
    var events: [String] = []
    let backgroundWindow = applicationWindow(
        number: 41,
        identifier: "agent-lifecycle",
        title: "Background Agent"
    )
    let mainWindow = applicationWindow(
        number: 42,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    let coordinator = InitialMainWindowPresentationCoordinator(
        availableWindows: { [backgroundWindow, mainWindow] },
        positionWindow: { events.append("position-\($0)") },
        dismissWindow: { events.append("dismiss-\($0)") },
        schedulePosition: { action in
            events.append("schedule-position")
            action()
        }
    )

    coordinator.apply(policy: .ordinary)

    #expect(events == ["schedule-position", "position-42"])
}

@MainActor
@Test func backgroundLifecycleSuppressesExistingAndLateNormalWindowsWithoutAView() {
    var events: [String] = []
    var isAccessory = false
    let mainWindow = applicationWindow(
        number: 42,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    let utilityWindow = ApplicationWindowDescriptor(
        windowNumber: 43,
        identifier: "utility",
        title: "Utility",
        canBecomeKey: false,
        isNormalLevel: false
    )
    let lateMainWindow = applicationWindow(
        number: 44,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    var windows = [mainWindow, utilityWindow]
    let hook = BackgroundApplicationLifecycleHook(
        policy: .backgroundScheduling,
        isAccessoryActivationPolicySet: { isAccessory },
        setAccessoryActivationPolicy: {
            isAccessory = true
            events.append("accessory")
        },
        acquireAutomaticTerminationHold: { events.append("hold") },
        releaseAutomaticTerminationHold: { events.append("release") },
        availableWindows: { windows },
        dismissWindow: { windowNumber in
            events.append("dismiss-\(windowNumber)")
            windows = windows.map { window in
                guard window.windowNumber == windowNumber else { return window }
                return ApplicationWindowDescriptor(
                    windowNumber: window.windowNumber,
                    identifier: window.identifier,
                    title: window.title,
                    canBecomeKey: window.canBecomeKey,
                    isVisible: false,
                    isNormalLevel: window.isNormalLevel
                )
            }
        }
    )

    hook.applicationWillFinishLaunching()
    hook.applicationDidFinishLaunching()
    hook.applicationDidUpdate()
    hook.windowDidBecomeVisible(lateMainWindow)
    hook.windowDidBecomeVisible(utilityWindow)
    hook.applicationWillTerminate()
    hook.applicationWillTerminate()

    #expect(events == ["accessory", "hold", "dismiss-42", "dismiss-44", "release"])
    #expect(hook.shouldObserveWindowVisibility)
    #expect(!hook.shouldTerminateAfterLastWindowClosed(defaultDecision: true))
}

@MainActor
@Test func backgroundLifecycleDismissesLateVisibleNonKeyWindowOnApplicationUpdate() {
    var events: [String] = []
    var isAccessory = false
    var windows: [ApplicationWindowDescriptor] = []
    let hook = BackgroundApplicationLifecycleHook(
        policy: .backgroundScheduling,
        isAccessoryActivationPolicySet: { isAccessory },
        setAccessoryActivationPolicy: {
            isAccessory = true
            events.append("accessory")
        },
        acquireAutomaticTerminationHold: { events.append("hold") },
        availableWindows: { windows },
        dismissWindow: { windowNumber in
            events.append("dismiss-\(windowNumber)")
            windows = windows.map { window in
                guard window.windowNumber == windowNumber else { return window }
                return ApplicationWindowDescriptor(
                    windowNumber: window.windowNumber,
                    identifier: window.identifier,
                    title: window.title,
                    canBecomeKey: window.canBecomeKey,
                    isVisible: false,
                    isNormalLevel: window.isNormalLevel
                )
            }
        }
    )

    hook.applicationDidFinishLaunching()
    windows = [ApplicationWindowDescriptor(
        windowNumber: 71,
        identifier: "late-non-key",
        title: "Late SwiftUI scene",
        canBecomeKey: false,
        isVisible: true,
        isNormalLevel: true
    )]
    hook.applicationDidUpdate()
    hook.applicationDidUpdate()

    #expect(events == ["accessory", "hold", "dismiss-71"])
}

@MainActor
@Test func backgroundLifecycleWindowRescanRejectsReentrantDismissal() {
    var events: [String] = []
    var windows = [applicationWindow(number: 72, identifier: "late", title: "Late window")]
    var hook: BackgroundApplicationLifecycleHook!
    hook = BackgroundApplicationLifecycleHook(
        policy: .backgroundScheduling,
        isAccessoryActivationPolicySet: { true },
        setAccessoryActivationPolicy: { events.append("unexpected-accessory") },
        availableWindows: { windows },
        dismissWindow: { windowNumber in
            events.append("dismiss-\(windowNumber)")
            hook.applicationDidUpdate()
            windows = []
        }
    )

    hook.applicationDidUpdate()
    hook.applicationDidUpdate()

    #expect(events == ["dismiss-72"])
}

@MainActor
@Test func ordinaryLifecycleLeavesActivationAndWindowsUntouched() {
    var events: [String] = []
    let hook = BackgroundApplicationLifecycleHook(
        policy: .ordinary,
        setAccessoryActivationPolicy: { events.append("accessory") },
        acquireAutomaticTerminationHold: { events.append("hold") },
        releaseAutomaticTerminationHold: { events.append("release") },
        availableWindows: {
            [applicationWindow(
                number: 42,
                identifier: MainApplicationWindowSelector.mainWindowIdentifier,
                title: "Zoid 666"
            )]
        },
        dismissWindow: { events.append("dismiss-\($0)") }
    )

    hook.applicationWillFinishLaunching()
    hook.applicationDidFinishLaunching()
    hook.applicationDidUpdate()
    hook.windowDidBecomeVisible(applicationWindow(
        number: 43,
        identifier: "late",
        title: "Late window"
    ))
    hook.applicationWillTerminate()

    #expect(events.isEmpty)
    #expect(!hook.shouldObserveWindowVisibility)
    #expect(hook.shouldTerminateAfterLastWindowClosed(defaultDecision: true))
    #expect(!hook.shouldTerminateAfterLastWindowClosed(defaultDecision: false))
}

@MainActor
@Test func backgroundLifecycleCancelsRepeatedStartupTerminationThenPermitsQuit() {
    var now: Double = 100
    let hook = BackgroundApplicationLifecycleHook(
        policy: .backgroundScheduling,
        setAccessoryActivationPolicy: {},
        availableWindows: { [] },
        dismissWindow: { _ in },
        currentTime: { now }
    )

    #expect(hook.applicationTerminationDecision() == .cancel)
    now = 105.999
    #expect(hook.applicationTerminationDecision() == .cancel)
    #expect(hook.applicationTerminationDecision() == .cancel)

    now = 106
    #expect(hook.applicationTerminationDecision() == .permit)
    now = 120
    #expect(hook.applicationTerminationDecision() == .permit)
}

@MainActor
@Test func ordinaryLifecycleAlwaysPermitsTermination() {
    var now: Double = 100
    let hook = BackgroundApplicationLifecycleHook(
        policy: .ordinary,
        setAccessoryActivationPolicy: {},
        availableWindows: { [] },
        dismissWindow: { _ in },
        currentTime: { now }
    )

    #expect(hook.applicationTerminationDecision() == .permit)
    now = 101
    #expect(hook.applicationTerminationDecision() == .permit)
}

@MainActor
@Test func ordinaryQAAndProductionLifecyclePoliciesAreStrictNoOps() {
    for packageMode in [RuntimePackageMode.qa, .production] {
        let presentation = ApplicationLaunchPresentation(
            arguments: ["ZoidCoach", "--qa-open-main"],
            packageMode: packageMode
        )
        var events: [String] = []
        let hook = BackgroundApplicationLifecycleHook(
            policy: presentation.initialMainWindowPresentationPolicy,
            setAccessoryActivationPolicy: { events.append("accessory") },
            acquireAutomaticTerminationHold: { events.append("hold") },
            releaseAutomaticTerminationHold: { events.append("release") },
            availableWindows: {
                [applicationWindow(number: 81, identifier: "main", title: "Zoid 666")]
            },
            dismissWindow: { events.append("dismiss-\($0)") }
        )

        hook.applicationWillFinishLaunching()
        hook.applicationDidFinishLaunching()
        hook.applicationDidUpdate()
        hook.applicationWillTerminate()

        #expect(events.isEmpty)
        #expect(hook.shouldTerminateAfterLastWindowClosed(defaultDecision: true))
        #expect(hook.applicationTerminationDecision() == .permit)
    }
}

@MainActor
@Test func qaMainWindowLaunchWaitsForTheMainWindowToExist() {
    var events: [String] = []
    var polls = 0
    let backgroundWindow = applicationWindow(
        number: 41,
        identifier: "agent-lifecycle",
        title: "Background Agent"
    )
    let mainWindow = applicationWindow(
        number: 42,
        identifier: MainApplicationWindowSelector.mainWindowIdentifier,
        title: "Zoid 666"
    )
    let coordinator = QAMainWindowOpeningCoordinator(
        requestMainWindow: { events.append("request-main") },
        activateApplication: { events.append("activate") },
        availableWindows: {
            polls += 1
            return polls == 1 ? [backgroundWindow] : [backgroundWindow, mainWindow]
        },
        foregroundWindow: { events.append("foreground-\($0)") },
        scheduleRetry: { action in
            events.append("retry")
            action()
        }
    )

    coordinator.open()

    #expect(events == ["request-main", "activate", "retry", "foreground-42"])
    #expect(polls == 2)
}

@MainActor
@Test func qaMainWindowLaunchStopsSafelyWhenTheMainWindowNeverExists() {
    var foregroundedWindows: [Int] = []
    var polls = 0
    var retries = 0
    let coordinator = QAMainWindowOpeningCoordinator(
        requestMainWindow: {},
        activateApplication: {},
        availableWindows: {
            polls += 1
            return [applicationWindow(
                number: 41,
                identifier: "agent-lifecycle",
                title: "Background Agent"
            )]
        },
        foregroundWindow: { foregroundedWindows.append($0) },
        scheduleRetry: { action in
            retries += 1
            action()
        },
        maximumForegroundAttempts: 3
    )

    coordinator.open()

    #expect(polls == 3)
    #expect(retries == 2)
    #expect(foregroundedWindows.isEmpty)
}

private func applicationWindow(
    number: Int,
    identifier: String?,
    title: String
) -> ApplicationWindowDescriptor {
    ApplicationWindowDescriptor(
        windowNumber: number,
        identifier: identifier,
        title: title,
        canBecomeKey: true,
        isNormalLevel: true
    )
}
