import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func notificationReplacementProbeExposesDistinctNativeAccessibilityIdentifiers() {
    #expect(QANotificationReplacementProbeAccessibility.identifiers == [
        "settings.qa-notification-replacement.original",
        "settings.qa-notification-replacement.updated",
        "settings.qa-notification-replacement.refresh",
        "settings.qa-notification-replacement.status",
    ])
    #expect(Set(QANotificationReplacementProbeAccessibility.identifiers).count == 4)
}

@Test
func notificationReplacementProbeRefusesProductionAndUnpackagedQA() throws {
    let fixture = try notificationReplacementFixture("availability")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let unpackaged = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", fixture.root.path],
        processEnvironment: [:],
        executableSigningIdentifier: nil
    ).environment

    #expect(!QANotificationReplacementProbe.isAvailable(in: .production()))
    #expect(!QANotificationReplacementProbe.isAvailable(in: unpackaged))
    #expect(QANotificationReplacementProbe.isAvailable(in: fixture.environment))

    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    let store = try notificationReplacementStore(fixture)
    let coordinator = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: fixture.environment
    )
    #expect(throws: QANotificationReplacementProbeError.unavailable) {
        _ = try QANotificationReplacementProbe(
            runtimeEnvironment: .production(),
            promptStore: store,
            notifications: coordinator,
            probeID: "refused-production",
            now: { fixture.now }
        )
    }
    #expect(throws: QANotificationReplacementProbeError.unavailable) {
        _ = try QANotificationReplacementProbe(
            runtimeEnvironment: unpackaged,
            promptStore: store,
            notifications: coordinator,
            probeID: "refused-unpackaged",
            now: { fixture.now }
        )
    }
}

@Test
func notificationReplacementProbeUsesStableIdentityForANewChangedEpisode() async throws {
    let fixture = try notificationReplacementFixture("replacement")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let store = try notificationReplacementStore(fixture)
    let coordinator = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: fixture.environment
    )
    let probe = try QANotificationReplacementProbe(
        runtimeEnvironment: fixture.environment,
        promptStore: store,
        notifications: coordinator,
        probeID: "zc-054-009",
        now: { fixture.now }
    )

    let original = try await probe.scheduleOriginal()
    let replacement = try await probe.scheduleReplacement()

    #expect(original.scheduled)
    #expect(replacement.scheduled)
    #expect(original.episode.id != replacement.episode.id)
    #expect(original.episode.decisionKey == replacement.episode.decisionKey)
    #expect(original.episode.title != replacement.episode.title)
    #expect(original.episode.summary != replacement.episode.summary)
    #expect(original.episode.type == PromptNotificationCategory.planReady.rawValue)
    #expect(replacement.episode.type == PromptNotificationCategory.planChanged.rawValue)
    #expect(original.episode.actions.map(\.kind) == [
        .acceptPlan,
        .reviewPlan,
        .snoozePlanning,
        .dismissPlanning,
    ])
    #expect(replacement.episode.actions.map(\.kind) == [.reviewPlan, .undoPlanChange])
    #expect(try store.episode(promptID: original.episode.id)?.state == .dismissed)
    #expect(replacement.episode.state.isUnresolved)
    #expect(
        PromptNotificationCoordinator.requestIdentifier(
            for: original.episode,
            notificationIdentity: fixture.environment.identity.notification
        ) == PromptNotificationCoordinator.requestIdentifier(
            for: replacement.episode,
            notificationIdentity: fixture.environment.identity.notification
        )
    )

    let notifications = try adapter.snapshot().notifications
    #expect(notifications.count == 1)
    #expect(notifications[0].desired.promptID == replacement.episode.id)
    #expect(notifications[0].desired.category == PromptNotificationCategory.planChanged.rawValue)
    #expect(notifications[0].desired.title == replacement.episode.title)
    #expect(notifications[0].desired.body == replacement.episode.summary)
}

@Test
func notificationReplacementProbeRoutesOnlyTheNewestActionAndSurvivesRelaunch() async throws {
    let fixture = try notificationReplacementFixture("action-relaunch")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let store = try notificationReplacementStore(fixture)
    let coordinator = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: fixture.environment
    )
    let probe = try QANotificationReplacementProbe(
        runtimeEnvironment: fixture.environment,
        promptStore: store,
        notifications: coordinator,
        probeID: "zc-054-009",
        now: { fixture.now }
    )
    let original = try await probe.scheduleOriginal()
    let replacement = try await probe.scheduleReplacement()
    _ = try adapter.respondToNotification(
        identifier: replacement.episode.id,
        actionIdentifier: PromptActionKind.undoPlanChange.rawValue
    )
    try await coordinator.processFixtureActions()

    #expect(try store.responses(promptID: original.episode.id).isEmpty)
    let latestResponses = try store.responses(promptID: replacement.episode.id)
    #expect(latestResponses.count == 1)
    #expect(latestResponses[0].surface == .notification)
    #expect(latestResponses[0].action == .undoPlanChange)

    let relaunchedAdapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    let relaunchedStore = try notificationReplacementStore(fixture)
    let relaunchedCoordinator = PromptNotificationCoordinator(
        promptStore: relaunchedStore,
        fixtureAdapter: relaunchedAdapter,
        runtimeEnvironment: fixture.environment
    )
    let relaunchedProbe = try QANotificationReplacementProbe(
        runtimeEnvironment: fixture.environment,
        promptStore: relaunchedStore,
        notifications: relaunchedCoordinator,
        probeID: "zc-054-009",
        now: { fixture.now }
    )
    let snapshot = try await relaunchedProbe.snapshot()

    #expect(snapshot.latestEpisode?.id == replacement.episode.id)
    #expect(snapshot.latestResponse?.promptID == replacement.episode.id)
    #expect(try relaunchedAdapter.snapshot().notifications.count == 1)
    #expect(try relaunchedAdapter.snapshot().notifications[0].desired.promptID == replacement.episode.id)
}

@Test
func notificationReplacementProbeKeepsDistinctLogicalDecisionsDistinct() async throws {
    let fixture = try notificationReplacementFixture("distinct")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: fixture.environment,
        clock: .fixed(fixture.now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let store = try notificationReplacementStore(fixture)
    let coordinator = PromptNotificationCoordinator(
        promptStore: store,
        fixtureAdapter: adapter,
        runtimeEnvironment: fixture.environment
    )
    let first = try QANotificationReplacementProbe(
        runtimeEnvironment: fixture.environment,
        promptStore: store,
        notifications: coordinator,
        probeID: "decision-a",
        now: { fixture.now }
    )
    let second = try QANotificationReplacementProbe(
        runtimeEnvironment: fixture.environment,
        promptStore: store,
        notifications: coordinator,
        probeID: "decision-b",
        now: { fixture.now }
    )

    let firstEpisode = try await first.scheduleOriginal().episode
    let secondEpisode = try await second.scheduleOriginal().episode
    let firstID = PromptNotificationCoordinator.requestIdentifier(
        for: firstEpisode,
        notificationIdentity: fixture.environment.identity.notification
    )
    let secondID = PromptNotificationCoordinator.requestIdentifier(
        for: secondEpisode,
        notificationIdentity: fixture.environment.identity.notification
    )

    #expect(firstID != secondID)
}

private struct NotificationReplacementFixture {
    let root: URL
    let environment: RuntimeEnvironment
    let now: Date
}

private final class NotificationReplacementIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return String(format: "qa-notification-replacement-%04d", value)
    }
}

private func notificationReplacementStore(
    _ fixture: NotificationReplacementFixture
) throws -> PromptInboxStore {
    let identifiers = NotificationReplacementIDSequence()
    return try PromptInboxStore(
        databaseURL: fixture.environment.databaseURL,
        now: { fixture.now },
        makeID: { identifiers.next() }
    )
}

private func notificationReplacementFixture(_ label: String) throws -> NotificationReplacementFixture {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot
        .appendingPathComponent(".build/notification-replacement-probe-tests", isDirectory: true)
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
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
    return NotificationReplacementFixture(
        root: root,
        environment: environment,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
