import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func intentionalGamingChoiceClosesPromptAndExplainsConfiguredOverride() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-dashboard-intentional-gaming-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let promptStore = try PromptInboxStore(databaseURL: root.appendingPathComponent("zoid.sqlite"), now: { now })
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "gaming-drift:2026-07-15:steam",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Is this gaming intentional?",
        summary: "Gaming is observed while priority work remains incomplete.",
        actions: [PromptAction(kind: .continueIntentionally, title: "Continue intentionally")],
        payload: ["taskID": "priority", "taskTitle": "Write proposal"]
    )).episode

    let result = try promptStore.respond(
        promptID: episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(promptID: episode.id, action: .continueIntentionally),
        surface: .dashboard
    )

    #expect(result.wasApplied)
    #expect(try promptStore.unresolved().isEmpty)
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .continueIntentionally,
        activeTaskID: nil
    ) == "Intentional gaming recorded. Equivalent gaming prompts are paused for your configured override window. Returning to aligned work ends the pause early.")
}

@Test
func intentionalGamingOutcomeRejectsNonGamingAndUnrelatedActions() {
    let gaming = PromptEpisode(
        id: "gaming",
        decisionKey: "gaming-drift:2026-07-15:steam",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Is this gaming intentional?",
        summary: "Gaming is observed.",
        actions: [],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let onboarding = PromptEpisode(
        id: "onboarding",
        decisionKey: "onboarding:test",
        type: PromptNotificationCategory.onboardingTest.rawValue,
        title: "Continue setup?",
        summary: "This is not a gaming override.",
        actions: [],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(DashboardPromptActionOutcome.successMessage(
        for: onboarding,
        action: .continueIntentionally,
        activeTaskID: nil
    ) == nil)
    #expect(DashboardPromptActionOutcome.successMessage(
        for: gaming,
        action: .ignore,
        activeTaskID: nil
    ) == nil)
}

@Test
func dashboardPromptStartsRecommendedTaskOnceAndProvidesVisibleOutcome() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-dashboard-prompt-start-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { now })
    let execution = try TaskExecutionStore(databaseURL: databaseURL)
    let router = PromptResponseEffectRouter(
        outbox: try ActionOutboxStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        promptStore: promptStore,
        taskExecution: execution
    )
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "dashboard:start:recommended",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Return to the plan",
        summary: "The recommended task is ready.",
        actions: [PromptAction(kind: .startRecommendedTask, title: "Start review")],
        payload: ["taskID": "review", "taskTitle": "Review migration risks"]
    )).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .startRecommendedTask)
    let first = try promptStore.respond(
        promptID: episode.id,
        action: .startRecommendedTask,
        actionToken: token,
        surface: .dashboard
    )
    let replay = try promptStore.respond(
        promptID: episode.id,
        action: .startRecommendedTask,
        actionToken: token,
        surface: .notification
    )

    #expect(try router.apply(first) == .coachingTaskStarted(taskID: "review"))
    #expect(try router.apply(replay) == .none)
    #expect(try execution.activeTask(now: now)?.taskID == "review")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .startRecommendedTask,
        activeTaskID: "review"
    ) == "Review migration risks is active in Today.")
}

@Test
func dashboardPromptStartOutcomeUsesHonestFallbackAndIgnoresOtherActions() {
    let episode = PromptEpisode(
        id: "prompt",
        decisionKey: "dashboard:start",
        type: "coaching",
        title: "Choose",
        summary: "Choose the next move.",
        actions: [],
        payload: ["taskID": "task"],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .startRecommendedTask,
        activeTaskID: "task"
    ) == "The recommended task is active in Today.")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .startRecommendedTask,
        activeTaskID: "another-task"
    ) == nil)
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .ignore,
        activeTaskID: "task"
    ) == nil)
}
