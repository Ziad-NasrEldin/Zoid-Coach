import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test func recommendationFeedbackPersistsDistinctUserChoicesAndHonorsTheirDurations() throws {
    let databaseURL = recommendationFeedbackDatabaseURL()
    defer { removeRecommendationFeedbackDatabase(databaseURL) }
    let store = try RecommendationFeedbackStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_784_000_000)

    let notNow = RecommendationFeedbackRequest(
        requestID: "recommendation-feedback-v1:not-now",
        taskID: "later",
        recommendationSentence: "Start Later",
        kind: .notNow,
        occurredAt: now
    )
    let wrongPriority = RecommendationFeedbackRequest(
        requestID: "recommendation-feedback-v1:wrong-priority",
        taskID: "wrong",
        recommendationSentence: "Start Wrong",
        kind: .wrongPriority,
        occurredAt: now
    )
    let tooLarge = RecommendationFeedbackRequest(
        requestID: "recommendation-feedback-v1:too-large",
        taskID: "large",
        recommendationSentence: "Start Large",
        kind: .tooLarge,
        occurredAt: now
    )
    let hiddenToday = RecommendationFeedbackRequest(
        requestID: "recommendation-feedback-v1:hidden-today",
        taskID: "hidden",
        recommendationSentence: "Start Hidden",
        kind: .hideToday,
        occurredAt: now
    )

    _ = try store.record(notNow, timeZoneIdentifier: "UTC")
    _ = try store.record(wrongPriority, timeZoneIdentifier: "UTC")
    _ = try store.record(tooLarge, timeZoneIdentifier: "UTC")
    _ = try store.record(hiddenToday, timeZoneIdentifier: "UTC")
    _ = try store.record(notNow, timeZoneIdentifier: "UTC")

    #expect(try store.suppressedTaskIDs(at: now.addingTimeInterval(60), timeZoneIdentifier: "UTC") == Set(["later", "wrong", "large", "hidden"]))
    #expect(try store.suppressedTaskIDs(at: now.addingTimeInterval(31 * 60), timeZoneIdentifier: "UTC") == Set(["wrong", "large", "hidden"]))
    #expect(try store.records(localDay: "2026-07-14").count == 4)

    let conflictingReplay = RecommendationFeedbackRequest(
        requestID: notNow.requestID,
        taskID: notNow.taskID,
        recommendationSentence: notNow.recommendationSentence,
        kind: .tooLarge,
        occurredAt: now
    )
    #expect(throws: RecommendationFeedbackStoreError.self) {
        try store.record(conflictingReplay, timeZoneIdentifier: "UTC")
    }
}

@Test func recommendationFeedbackSelectsAnotherReadyTaskAndSurvivesAgentRestart() throws {
    let databaseURL = recommendationFeedbackDatabaseURL()
    defer { removeRecommendationFeedbackDatabase(databaseURL) }
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "first", title: "First priority", dueDate: now, priority: 9),
        ReminderSourceSnapshot(id: "second", title: "Smaller next task", dueDate: nil, priority: 5)
    ])
    _ = try PolicyStore(databaseURL: databaseURL).saveSystemMaintenancePolicy(
        .defaults(timeZoneIdentifier: "UTC")
    )
    try AutonomousPlanStore(databaseURL: databaseURL).replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "first", title: "First priority", rank: 1, estimateMinutes: 60, reason: "Main objective", score: 100),
                PlannedTask(taskID: "second", title: "Smaller next task", rank: 2, estimateMinutes: 20, reason: "Fits now", score: 60)
            ],
            mainObjectiveTaskID: "first",
            plannedFocusMinutes: 80,
            availableFocusMinutes: 120
        ),
        for: now
    )
    let agent = try TodayDashboardAgent(databaseURL: databaseURL)
    #expect(try agent.snapshot(now: now).recommendation.taskID == "first")

    let store = try RecommendationFeedbackStore(databaseURL: databaseURL)
    _ = try store.record(
        RecommendationFeedbackRequest(
            requestID: "recommendation-feedback-v1:agent-restart",
            taskID: "first",
            recommendationSentence: "Start First priority",
            kind: .wrongPriority,
            occurredAt: now
        ),
        timeZoneIdentifier: "UTC"
    )

    #expect(try agent.snapshot(now: now.addingTimeInterval(1)).recommendation.taskID == "second")
    let restartedAgent = try TodayDashboardAgent(databaseURL: databaseURL)
    #expect(try restartedAgent.snapshot(now: now.addingTimeInterval(120)).recommendation.taskID == "second")
}

@Test func recommendationFeedbackCommandRoundTripsAllChoices() throws {
    for kind in RecommendationFeedbackKind.allCases {
        let command = AgentMutationCommand.recordRecommendationFeedback(
            RecommendationFeedbackRequest(
                requestID: "recommendation-feedback-v1:\(kind.rawValue)",
                taskID: "task",
                recommendationSentence: "Start task",
                kind: kind,
                occurredAt: Date(timeIntervalSince1970: 1_784_000_000)
            )
        )
        let data = try JSONEncoder().encode(command)
        #expect(try JSONDecoder().decode(AgentMutationCommand.self, from: data) == command)
    }
}

@Test func recommendationFeedbackPersistsThroughTheAgentMutationBoundary() async throws {
    let databaseURL = recommendationFeedbackDatabaseURL()
    defer { removeRecommendationFeedbackDatabase(databaseURL) }
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    let router = AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyRecommendationFeedbackCalendar()
        ),
        policyStore: try PolicyStore(databaseURL: databaseURL),
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL),
        recommendationFeedback: try RecommendationFeedbackStore(databaseURL: databaseURL)
    )
    let request = RecommendationFeedbackRequest(
        requestID: "recommendation-feedback-v1:agent-boundary",
        taskID: "priority",
        recommendationSentence: "Start Priority",
        kind: .tooLarge
    )

    let receipt = try await router.apply(.recordRecommendationFeedback(request))

    #expect(receipt.accepted)
    #expect(receipt.message == RecommendationFeedbackKind.tooLarge.confirmationMessage)
    let events = try DomainEventStore(databaseURL: databaseURL).events()
    #expect(events.contains {
        $0.id == request.requestID
            && $0.type == RecommendationFeedbackStore.eventType
            && $0.entityID == request.taskID
            && $0.payload["kind"] == RecommendationFeedbackKind.tooLarge.rawValue
    })
}

private struct EmptyRecommendationFeedbackCalendar: CalendarAvailabilitySource {
    func commitments(
        from start: Date,
        through end: Date,
        calendarIdentifiers: [String]
    ) async throws -> [CalendarCommitment] {
        []
    }
}

private func recommendationFeedbackDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-recommendation-feedback-\(UUID().uuidString).sqlite")
}

private func removeRecommendationFeedbackDatabase(_ databaseURL: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
    }
}
