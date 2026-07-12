import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func onboardingTestPromptIsCanonicalIdempotentAndDurablyResolved() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("onboarding-prompt-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let store = try PromptInboxStore(
        databaseURL: runtime.databaseURL,
        makeID: { "onboarding-prompt-1" }
    )
    let notifications = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: runtime
    )
    let service = OnboardingTestPromptService(store: store, notifications: notifications)

    let first = try await service.createOrDeliver(flowID: "flow-1")
    let replay = try await service.createOrDeliver(flowID: "flow-1")

    #expect(first.episode.id == "onboarding-prompt-1")
    #expect(replay.episode.id == first.episode.id)
    #expect(first.delivery == .notification)
    #expect(try store.unresolved().count == 1)
    #expect(first.episode.actions.map(\.kind) == [.continueIntentionally, .ignore])

    let resolved = try store.respond(
        promptID: first.episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(
            promptID: first.episode.id,
            action: .continueIntentionally
        ),
        surface: .loopback
    ).episode
    let afterRestart = try OnboardingTestPromptService(
        store: PromptInboxStore(databaseURL: runtime.databaseURL),
        notifications: notifications
    ).current(flowID: "flow-1")

    #expect(resolved.state == .responded)
    #expect(afterRestart?.id == resolved.id)
    #expect(afterRestart?.state == .responded)
}

@Test
func onboardingTestPromptFallsBackToTodayWhenNotificationsAreDenied() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("onboarding-prompt-denied-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
    try adapter.reset(to: .init(permissions: [.notifications: .denied]))
    let store = try PromptInboxStore(databaseURL: runtime.databaseURL)
    let notifications = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: runtime
    )
    let service = OnboardingTestPromptService(store: store, notifications: notifications)

    let result = try await service.createOrDeliver(flowID: "flow-denied")

    #expect(result.delivery == .todayFallback)
    #expect(try store.unresolved().map(\.id) == [result.episode.id])
}
