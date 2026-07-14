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

@MainActor
@Test func qaMainWindowLaunchIsForegroundedExactlyOnce() {
    var events: [String] = []
    let coordinator = QAMainWindowOpeningCoordinator(
        requestMainWindow: { events.append("request-main") },
        activateApplication: { events.append("activate") },
        foregroundMainWindow: { events.append("foreground-main") },
        deferForeground: { action in
            events.append("defer")
            action()
        }
    )
    var gate = QAMainWindowLaunchGate()

    gate.openIfNeeded(shouldOpenMainWindow: false, coordinator: coordinator)
    gate.openIfNeeded(shouldOpenMainWindow: true, coordinator: coordinator)
    gate.openIfNeeded(shouldOpenMainWindow: true, coordinator: coordinator)

    #expect(events == ["request-main", "activate", "defer", "foreground-main"])
    #expect(gate.hasOpenedMainWindow)
}
