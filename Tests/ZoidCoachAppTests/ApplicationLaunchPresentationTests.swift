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
