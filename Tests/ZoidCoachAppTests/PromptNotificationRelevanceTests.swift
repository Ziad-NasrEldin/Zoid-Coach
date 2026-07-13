import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func promptNotificationRelevanceGroupsPlanningUpdatesWithoutCollapsingOtherDecisions() {
    let planning = PromptNotificationRelevance(category: .planReady)

    #expect(planning.includes(.planReady))
    #expect(planning.includes(.planChanged))
    #expect(!planning.includes(.meetingCandidate))
    #expect(PromptNotificationRelevance(category: .gamingDrift).categories == [.gamingDrift])
}

@Test
func latestRelevantNotificationReplacesOnlyItsGroupAndPreservesEveryDashboardPrompt() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-latest-notification-\(UUID().uuidString)", isDirectory: true)
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
    let promptStore = try PromptInboxStore(databaseURL: runtime.databaseURL, now: { now })
    let coordinator = PromptNotificationCoordinator(
        promptStore: promptStore,
        fixtureAdapter: adapter,
        runtimeEnvironment: runtime
    )
    let earlierPlan = try promptStore.enqueue(.init(
        decisionKey: "plan:earlier",
        type: PromptNotificationCategory.planReady.rawValue,
        title: "Earlier plan",
        summary: "The first plan is ready.",
        actions: [.init(kind: .reviewPlan, title: "Review")]
    )).episode
    let meeting = try promptStore.enqueue(.init(
        decisionKey: "meeting:one",
        type: PromptNotificationCategory.meetingCandidate.rawValue,
        title: "Meeting found",
        summary: "Review this meeting separately.",
        actions: [.init(kind: .addMeeting, title: "Add")]
    )).episode
    let changedPlan = try promptStore.enqueue(.init(
        decisionKey: "plan:changed",
        type: PromptNotificationCategory.planChanged.rawValue,
        title: "Plan changed",
        summary: "This is the latest plan decision.",
        actions: [.init(kind: .reviewPlan, title: "Review")]
    )).episode

    #expect(try await coordinator.schedule(earlierPlan))
    #expect(try await coordinator.schedule(meeting))
    #expect(try await coordinator.schedule(changedPlan))

    var notifications = try adapter.snapshot().notifications
    #expect(Set(notifications.compactMap(\.desired.promptID)) == [meeting.id, changedPlan.id])
    #expect(Set(try promptStore.unresolved().map(\.id)) == [earlierPlan.id, meeting.id, changedPlan.id])

    let earlierDrift = try promptStore.enqueue(.init(
        decisionKey: "drift:earlier",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Earlier coaching choice",
        summary: "This choice remains in Today.",
        actions: [.init(kind: .continueIntentionally, title: "Continue intentionally")]
    )).episode
    let latestDrift = try promptStore.enqueue(.init(
        decisionKey: "drift:latest",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Latest coaching choice",
        summary: "This is the latest relevant notification.",
        actions: [.init(kind: .returnToActiveTask, title: "Return")]
    )).episode

    #expect(try await coordinator.schedule(earlierDrift))
    #expect(try await coordinator.schedule(latestDrift))

    notifications = try adapter.snapshot().notifications
    #expect(Set(notifications.compactMap(\.desired.promptID)) == [meeting.id, changedPlan.id, latestDrift.id])
    #expect(!notifications.contains { $0.desired.promptID == earlierPlan.id })
    #expect(!notifications.contains { $0.desired.promptID == earlierDrift.id })
    #expect(Set(try promptStore.unresolved().map(\.id)) == [
        earlierPlan.id, meeting.id, changedPlan.id, earlierDrift.id, latestDrift.id
    ])
}
