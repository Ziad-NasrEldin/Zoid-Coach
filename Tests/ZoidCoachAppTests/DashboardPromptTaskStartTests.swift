import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

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

@Test
func dashboardAmbiguityOutcomesConfirmExactlyWhatChanged() {
    let episode = PromptEpisode(
        id: "ambiguity-prompt",
        decisionKey: "ambiguous-activity:2026-07-15:1:task",
        type: AmbiguousActivityPromptService.promptType,
        title: "Did this support Ship proposal?",
        summary: "Application and duration alone cannot show intent.",
        actions: [],
        payload: ["taskID": "task", "taskTitle": "Ship proposal"],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .classifyAsSupportingWork,
        activeTaskID: "task"
    ) == "The observed session is now counted as supporting work for Ship proposal.")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .classifyAsGaming,
        activeTaskID: "task"
    ) == "The observed session is now counted as gaming.")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .keepActivityUnknown,
        activeTaskID: "task"
    ) == "The observed session remains unknown. Coaching was not changed.")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: episode,
        action: .ignore,
        activeTaskID: "task"
    ) == nil)
}

@Test
func dashboardAmbiguityOutcomeUsesHonestTaskFallbackAndDoesNotAffectOtherPrompts() {
    let ambiguity = PromptEpisode(
        id: "ambiguity-prompt",
        decisionKey: "ambiguous-activity:2026-07-15:1:task",
        type: AmbiguousActivityPromptService.promptType,
        title: "Was this supporting work?",
        summary: "Application and duration alone cannot show intent.",
        actions: [],
        payload: ["taskID": "task", "taskTitle": "   "],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let unrelated = PromptEpisode(
        id: "other",
        decisionKey: "other",
        type: "OTHER",
        title: "Other",
        summary: "Other decision.",
        actions: [],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(DashboardPromptActionOutcome.successMessage(
        for: ambiguity,
        action: .classifyAsSupportingWork,
        activeTaskID: nil
    ) == "The observed session is now counted as supporting work for the active task.")
    #expect(DashboardPromptActionOutcome.successMessage(
        for: unrelated,
        action: .classifyAsGaming,
        activeTaskID: nil
    ) == nil)
}
