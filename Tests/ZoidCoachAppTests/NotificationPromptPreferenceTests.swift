import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func notificationPromptPreferenceDefaultsOnAndRoundTripsThroughSettings() throws {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let encoded = try JSONEncoder().encode(original.privacy)
    let decodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    var legacyObject = try #require(decodedObject)
    legacyObject.removeValue(forKey: "notificationPromptsEnabled")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacy = try JSONDecoder().decode(PrivacyPolicy.self, from: legacyData)

    #expect(legacy.effectiveNotificationPromptsEnabled)

    var draft = SettingsPolicyDraft(policy: original)
    draft.notificationPromptsEnabled = false
    let saved = draft.policy(preserving: original)

    #expect(saved.privacy.effectiveNotificationPromptsEnabled == false)
    #expect(SettingsPolicyDraft(policy: saved).notificationPromptsEnabled == false)
    #expect(saved.validationViolations().isEmpty)
}

@Test
func notificationPromptPreferenceSurvivesAnIndependentSettingsConflict() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let base = SettingsPolicyDraft(policy: original)
    var mine = base
    mine.notificationPromptsEnabled = false
    var current = base
    current.capacityPercent = 55

    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(merged.safeDraft.notificationPromptsEnabled == false)
    #expect(merged.safeDraft.capacityPercent == 55)
    #expect(merged.concurrentChanges == ["Planning capacity"])
    #expect(merged.overlappingChanges.isEmpty)
}

@Test
func disabledPromptNotificationsRemainInAppAndCanBeReenabledWithoutRestart() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-notification-preference-\(UUID().uuidString)", isDirectory: true)
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
    try adapter.reset(to: .init(permissions: [.notifications: .granted]))
    let promptStore = try PromptInboxStore(
        databaseURL: runtime.databaseURL,
        now: { now },
        makeID: { UUID().uuidString }
    )
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "notification-preference",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "A choice is ready",
        summary: "This choice remains available in Today.",
        actions: [PromptAction(kind: .continueIntentionally, title: "Continue intentionally")]
    )).episode
    let gate = NotificationPromptGate(isEnabled: true)
    let coordinator = PromptNotificationCoordinator(
        promptStore: promptStore,
        fixtureAdapter: adapter,
        runtimeEnvironment: runtime,
        promptNotificationsEnabled: { gate.isEnabled }
    )

    #expect(try await coordinator.schedule(episode))
    #expect(try await coordinator.scheduleAcceptedBreakEnd(
        taskID: "local:focus",
        taskTitle: "Focus task",
        startedAt: now,
        deliveryDate: now.addingTimeInterval(15 * 60)
    ))
    #expect(try adapter.snapshot().notifications.count == 2)

    gate.isEnabled = false
    try await coordinator.reconcilePromptNotificationPreference()
    let notificationsAfterDisabling = try adapter.snapshot().notifications
    #expect(notificationsAfterDisabling.count == 1)
    #expect(!notificationsAfterDisabling.contains { $0.desired.promptID == episode.id })
    #expect(try promptStore.unresolved().map(\.id) == [episode.id])

    let episodeAfterDisabling = try promptStore.enqueue(PromptDraft(
        decisionKey: "notification-preference-while-disabled",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Another choice is ready",
        summary: "This new choice is available in Today without a notification.",
        actions: [PromptAction(kind: .continueIntentionally, title: "Continue intentionally")]
    )).episode
    let deliveryCountBeforeSuppressedSchedule = try NotificationDeliveryLedger(
        databaseURL: runtime.databaseURL
    ).recent().count
    #expect(try await coordinator.schedule(episodeAfterDisabling) == false)
    #expect(try adapter.snapshot().notifications.count == 1)
    #expect(try NotificationDeliveryLedger(
        databaseURL: runtime.databaseURL
    ).recent().count == deliveryCountBeforeSuppressedSchedule)

    gate.isEnabled = true
    #expect(try await coordinator.schedule(episodeAfterDisabling))
    let notifications = try adapter.snapshot().notifications
    #expect(notifications.count == 2)
    #expect(notifications.contains { $0.desired.promptID == episodeAfterDisabling.id })
    #expect(Set(try promptStore.unresolved().map(\.id)) == [episode.id, episodeAfterDisabling.id])
}

private final class NotificationPromptGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    init(isEnabled: Bool) {
        enabled = isEnabled
    }

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }
}
