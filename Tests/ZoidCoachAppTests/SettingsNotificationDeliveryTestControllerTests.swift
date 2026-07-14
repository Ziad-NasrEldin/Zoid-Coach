import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func settingsNotificationTestShowsExactOutcomeAndSupportsRetry() async {
    let recorder = NotificationDeliveryTestRecorder(results: [
        OnboardingDeliveryResult(state: .scheduled, message: "macOS accepted the test."),
        OnboardingDeliveryResult(state: .failed, message: "Delivery failed. Use Today.")
    ])
    let controller = SettingsNotificationDeliveryTestController {
        await recorder.next()
    }

    #expect(controller.buttonTitle == "SEND TEST NOTIFICATION")
    controller.sendTest()
    await waitForNotificationResult(controller)
    #expect(controller.result == OnboardingDeliveryResult(state: .scheduled, message: "macOS accepted the test."))
    #expect(controller.buttonTitle == "SEND ANOTHER TEST")

    controller.sendTest()
    await waitForNotificationResult(controller, expectedMessage: "Delivery failed. Use Today.")
    #expect(controller.result == OnboardingDeliveryResult(state: .failed, message: "Delivery failed. Use Today."))
    #expect(await recorder.callCount() == 2)
}

@MainActor
@Test
func settingsNotificationTestSuppressesDuplicateClicksWhileRunning() async {
    let gate = NotificationDeliveryTestGate()
    let controller = SettingsNotificationDeliveryTestController {
        await gate.run()
    }

    controller.sendTest()
    controller.sendTest()
    while await gate.callCount() == 0 { await Task.yield() }

    #expect(controller.isRunning)
    #expect(controller.buttonTitle == "SENDING TEST")
    #expect(await gate.callCount() == 1)

    await gate.finish(OnboardingDeliveryResult(
        state: .unavailable,
        message: "Notifications are not enabled. Coaching choices remain available in Today."
    ))
    await waitForNotificationResult(controller)

    #expect(controller.result?.state == .unavailable)
    #expect(controller.result?.message.contains("available in Today") == true)
}

@MainActor
@Test
func signedQALiveNotificationModeRequiresExplicitIsolatedMarker() throws {
    let fixture = try settingsNotificationTestFixture("live-marker")
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    #expect(!SettingsNotificationDeliveryTestController.shouldUseLiveSystemCenter(
        runtimeEnvironment: fixture.environment
    ))
    let marker = fixture.root.appendingPathComponent(
        SettingsNotificationDeliveryTestController.liveQAMarkerRelativePath
    )
    try FileManager.default.createDirectory(
        at: marker.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: marker.path, contents: Data()))
    #expect(SettingsNotificationDeliveryTestController.shouldUseLiveSystemCenter(
        runtimeEnvironment: fixture.environment
    ))

    let unpackaged = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", fixture.root.path],
        processEnvironment: [:]
    ).environment
    #expect(!SettingsNotificationDeliveryTestController.shouldUseLiveSystemCenter(
        runtimeEnvironment: unpackaged
    ))
}

@MainActor
@Test
func unpackagedQACannotUseSystemNotificationsEvenWhenLiveFlagIsRequested() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-notification-test-unpackaged-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let environment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let recorder = SystemNotificationTestRecorder(authorization: .authorized)
    let ledger = try NotificationDeliveryLedger(databaseURL: environment.databaseURL)
    let service = OnboardingDeliveryTestService(
        runtimeEnvironment: environment,
        fixtureAdapter: nil,
        useLiveSystemCenterInPackagedQA: true,
        systemClient: recorder.client,
        ledger: ledger
    )

    let result = await service.run()

    #expect(result.state == .unavailable)
    #expect(result.message.contains("No production notification API was used") == true)
    #expect(await recorder.requests().isEmpty)
    #expect(try ledger.recent().first?.outcome == .authorizationUnavailable)
}

@MainActor
@Test
func signedQAAuthorizedSystemTestPersistsPrivacySafeRelaunchHistory() async throws {
    let fixture = try settingsNotificationTestFixture("authorized")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = SystemNotificationTestRecorder(authorization: .authorized)
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.environment.databaseURL)
    let service = OnboardingDeliveryTestService(
        runtimeEnvironment: fixture.environment,
        fixtureAdapter: nil,
        useLiveSystemCenterInPackagedQA: true,
        systemClient: recorder.client,
        ledger: ledger
    )

    let result = await service.run()

    #expect(result.state == .scheduled)
    #expect(result.message.contains("macOS accepted") == true)
    let requests = await recorder.requests()
    #expect(requests.count == 1)
    #expect(requests[0].title == "Zoid 666 is ready")
    #expect(requests[0].body == "This is the delivery check. No action is required.")
    let reopened = try NotificationDeliveryLedger(databaseURL: fixture.environment.databaseURL)
    let records = try reopened.recent()
    #expect(records.count == 1)
    #expect(records[0].outcome == .acceptedBySystem)
    #expect(records[0].category == PromptNotificationCategory.onboardingTest.rawValue)
    #expect(records[0].redactedError == nil)
}

@MainActor
@Test
func signedQADeniedSystemTestShowsExactRepairWithoutScheduling() async throws {
    let fixture = try settingsNotificationTestFixture("denied")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = SystemNotificationTestRecorder(authorization: .unavailable)
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.environment.databaseURL)
    let service = OnboardingDeliveryTestService(
        runtimeEnvironment: fixture.environment,
        fixtureAdapter: nil,
        useLiveSystemCenterInPackagedQA: true,
        systemClient: recorder.client,
        ledger: ledger
    )

    let result = await service.run()

    #expect(result.state == .unavailable)
    #expect(result.message.contains("System Settings > Notifications > Zoid 666 > Allow Notifications") == true)
    #expect(result.message.contains("Today") == true)
    #expect(await recorder.requests().isEmpty)
    #expect(try ledger.recent().first?.outcome == .authorizationUnavailable)
}

@MainActor
@Test
func systemSchedulingFailureKeepsPrivateDiagnosticsOutOfVisibleCopy() async throws {
    let fixture = try settingsNotificationTestFixture("failure")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = SystemNotificationTestRecorder(
        authorization: .authorized,
        error: SettingsNotificationTestFailure(
            detail: "failed at /Users/person/private.txt for person@example.com"
        )
    )
    let ledger = try NotificationDeliveryLedger(databaseURL: fixture.environment.databaseURL)
    let service = OnboardingDeliveryTestService(
        runtimeEnvironment: fixture.environment,
        fixtureAdapter: nil,
        useLiveSystemCenterInPackagedQA: true,
        systemClient: recorder.client,
        ledger: ledger
    )

    let result = await service.run()

    #expect(result.state == .failed)
    #expect(!result.message.contains("/Users"))
    #expect(!result.message.contains("person@example.com"))
    #expect(result.message.contains("System Settings > Notifications > Zoid 666") == true)
    let diagnostic = try ledger.recent().first?.redactedError
    #expect(diagnostic?.contains("[path]") == true)
    #expect(diagnostic?.contains("[address]") == true)
    #expect(diagnostic?.contains("private.txt") == false)
}

@MainActor
private func waitForNotificationResult(
    _ controller: SettingsNotificationDeliveryTestController,
    expectedMessage: String? = nil
) async {
    for _ in 0..<100 {
        if let result = controller.result,
           expectedMessage == nil || result.message == expectedMessage {
            return
        }
        await Task.yield()
    }
}

private actor NotificationDeliveryTestRecorder {
    private var results: [OnboardingDeliveryResult]
    private var calls = 0

    init(results: [OnboardingDeliveryResult]) {
        self.results = results
    }

    func next() -> OnboardingDeliveryResult {
        calls += 1
        return results.removeFirst()
    }

    func callCount() -> Int { calls }
}

private actor NotificationDeliveryTestGate {
    private var calls = 0
    private var continuation: CheckedContinuation<OnboardingDeliveryResult, Never>?

    func run() async -> OnboardingDeliveryResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func callCount() -> Int { calls }

    func finish(_ result: OnboardingDeliveryResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private struct SettingsNotificationTestFixture {
    let root: URL
    let environment: RuntimeEnvironment
}

private func settingsNotificationTestFixture(_ label: String) throws -> SettingsNotificationTestFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-notification-test-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let environment = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    return SettingsNotificationTestFixture(root: root, environment: environment)
}

private actor SystemNotificationTestRecorder {
    struct Request: Equatable {
        let identifier: String
        let title: String
        let body: String
    }

    private let authorization: NotificationDeliveryTestSystemClient.Authorization
    private let error: Error?
    private var recordedRequests: [Request] = []

    init(
        authorization: NotificationDeliveryTestSystemClient.Authorization,
        error: Error? = nil
    ) {
        self.authorization = authorization
        self.error = error
    }

    nonisolated var client: NotificationDeliveryTestSystemClient {
        NotificationDeliveryTestSystemClient(
            authorization: { await self.authorizationValue() },
            schedule: { identifier, title, body in
                try await self.record(identifier: identifier, title: title, body: body)
            }
        )
    }

    func requests() -> [Request] { recordedRequests }

    private func authorizationValue() -> NotificationDeliveryTestSystemClient.Authorization {
        authorization
    }

    private func record(identifier: String, title: String, body: String) throws {
        if let error { throw error }
        recordedRequests.append(Request(identifier: identifier, title: title, body: body))
    }
}

private struct SettingsNotificationTestFailure: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
