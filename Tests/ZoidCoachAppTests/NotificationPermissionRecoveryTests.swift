import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func deniedFallbackRepairReplacementAndInterruptedResponseRemainOneJourney() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("notification-recovery-(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
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
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
        runtimeEnvironment: runtime,
        clock: .fixed(now)
    )
    try adapter.reset(to: .init(permissions: [.notifications: .denied]))
    let promptStore = try PromptInboxStore(
        databaseURL: runtime.databaseURL,
        now: { now },
        makeID: { "recovery-prompt" }
    )
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "notification-recovery",
        type: PromptNotificationCategory.onboardingTest.rawValue,
        title: "Choose where coaching continues",
        summary: "The same choice remains in Today.",
        actions: [
            PromptAction(kind: .continueIntentionally, title: "Continue"),
            PromptAction(kind: .ignore, title: "Use Today")
        ]
    )).episode
    let responses = NotificationResponseCounter()
    let coordinator = PromptNotificationCoordinator(
        promptStore: promptStore,
        fixtureAdapter: adapter,
        runtimeEnvironment: runtime,
        onResponse: { _ in responses.increment() }
    )

    #expect(try await coordinator.schedule(episode) == false)
    #expect(try promptStore.unresolved().map { $0.id } == [episode.id])
    #expect(try adapter.snapshot().notifications.isEmpty)
    let deniedRecords = try NotificationDeliveryLedger(
        databaseURL: runtime.databaseURL,
        now: { now }
    ).recent()
    #expect(deniedRecords.count == 1)
    #expect(deniedRecords[0].outcome == .authorizationUnavailable)

    try adapter.setPermission(.granted, for: .notifications)
    #expect(try await coordinator.schedule(episode))
    #expect(try await coordinator.schedule(episode))
    let delivered = try adapter.snapshot().notifications
    #expect(delivered.count == 1)
    #expect(delivered[0].desired.promptID == episode.id)
    let repairedRecords = try NotificationDeliveryLedger(
        databaseURL: runtime.databaseURL,
        now: { now }
    ).recent()
    #expect(repairedRecords.count == 3)
    #expect(repairedRecords[0].replacedPriorRequest)

    _ = try QAFixtureOSComposition.apply(
        QAFixtureOSControlRequest(
            requestID: "notification-recovery-response",
            operation: .notificationAction,
            notificationID: episode.id,
            actionIdentifier: PromptActionKind.continueIntentionally.rawValue
        ),
        runtimeEnvironment: runtime,
        to: adapter
    )
    try await coordinator.processFixtureActions()
    try await coordinator.processFixtureActions()

    #expect(responses.value == 1)
    #expect(try promptStore.episode(promptID: episode.id)?.state == .responded)
    #expect(try promptStore.unresolved().isEmpty)
}

private final class NotificationResponseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
