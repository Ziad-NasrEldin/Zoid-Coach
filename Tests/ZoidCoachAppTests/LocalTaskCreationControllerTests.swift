import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func localTaskControllerTrimsDraftAndPreservesItsIdentityAcrossRetry() async throws {
    let client = LocalTaskTestClient(failFirst: true)
    let day = Date(timeIntervalSince1970: 1_720_000_000)
    let controller = LocalTaskCreationController(
        client: client,
        now: { day },
        makeID: { "local:user:stable-retry" }
    )
    controller.title = "  Write the proposal  "
    controller.notes = "  Include the revised scope  "
    controller.estimateMinutes = 45
    controller.isTechnicalTask = true

    #expect(await controller.save() == false)
    #expect(controller.errorMessage != nil)
    #expect(controller.title == "  Write the proposal  ")
    #expect(await controller.save())

    let submissions = await client.submissions
    #expect(submissions.count == 2)
    #expect(submissions[0] == submissions[1])
    #expect(submissions[1].task.id == "local:user:stable-retry")
    #expect(submissions[1].task.title == "Write the proposal")
    #expect(submissions[1].task.notes == "Include the revised scope")
    #expect(submissions[1].task.estimateMinutes == 45)
    #expect(submissions[1].task.declaredContext == .technical)
    #expect(submissions[1].addToToday)
    #expect(submissions[1].day == day)
}

@Test
func legacyLocalTaskCommandDecodesWithoutDeclaredContext() throws {
    let task = AgentLocalTask(
        id: "local:user:legacy",
        title: "Legacy general task",
        notes: nil,
        estimateMinutes: 30
    )
    let command = AgentMutationCommand.createLocalTask(
        task: task,
        addToToday: true,
        day: Date(timeIntervalSince1970: 1_720_000_000)
    )
    let encoded = try JSONEncoder().encode(command)
    #expect(String(decoding: encoded, as: UTF8.self).contains("declaredContext") == false)
    let decoded = try JSONDecoder().decode(AgentMutationCommand.self, from: encoded)

    guard case let .createLocalTask(decodedTask, _, _) = decoded else {
        Issue.record("Expected createLocalTask command")
        return
    }
    #expect(decodedTask.declaredContext == nil)
}

@Test
func agentOwnedLocalTaskCreationIsIdempotentDurableAndPartOfTodaysPlan() async throws {
    let databaseURL = temporaryLocalTaskDatabaseURL()
    defer { removeLocalTaskDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_720_008_000)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    let router = try makeLocalTaskRouter(databaseURL: databaseURL, reminders: reminders)
    let command = AgentMutationCommand.createLocalTask(
        task: AgentLocalTask(
            id: "local:user:proposal",
            title: "Write proposal",
            notes: "Use the approved scope",
            estimateMinutes: 50,
            declaredContext: .technical
        ),
        addToToday: true,
        day: day
    )

    #expect(try await router.apply(command).accepted)
    #expect(try await router.apply(command).accepted)
    await #expect(throws: ReminderSnapshotStoreError.self) {
        try await router.apply(.createLocalTask(
            task: AgentLocalTask(
                id: "local:user:proposal",
                title: "A different task",
                notes: nil,
                estimateMinutes: 20
            ),
            addToToday: true,
            day: day
        ))
    }

    let reopenedReminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    let local = try reopenedReminders.loadIncomplete().first { $0.id == "local:user:proposal" }
    #expect(local?.sourceKind == .local)
    #expect(local?.title == "Write proposal")
    #expect(local?.listID == "local:user")
    #expect(local?.listName == "Local Tasks")
    #expect(local?.notes == "Use the approved scope")
    #expect(local?.declaredContext == .technical)

    let plan = try AutonomousPlanStore(databaseURL: databaseURL).loadDailyPlan(for: day)
    #expect(plan.count == 1)
    #expect(plan.first?.reminderID == "local:user:proposal")
    #expect(plan.first?.estimateMinutes == 50)
    #expect(plan.first?.isMainObjective == true)

    let dashboard = try TodayDashboardAgent(databaseURL: databaseURL).snapshot(now: day)
    #expect(dashboard.taskRows.first { $0.taskID == "local:user:proposal" }?.declaredContext == .technical)

    _ = try reopenedReminders.synchronize([
        ReminderSourceSnapshot(id: "external", title: "External task", dueDate: nil, priority: 0)
    ])
    #expect(try reopenedReminders.loadIncomplete().contains { $0.id == "local:user:proposal" })
    #expect(try reopenedReminders.snapshot(forID: "external")?.declaredContext == nil)
}

@Test
func declaredTechnicalContextSurvivesLivePlanRefreshAndWinsOverTitleInference() {
    let snapshot = TodayTaskRow(
        taskID: "local:user:technical",
        title: "Write proposal",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .low,
        state: .active,
        elapsedMinutes: 12,
        isMainObjective: true,
        declaredContext: .technical
    )
    let plan = DailyPlanEntry(
        reminderID: snapshot.taskID,
        rank: 0,
        isMainObjective: true,
        estimateMinutes: 45,
        selectionReason: nil,
        selectionScore: nil
    )

    let refreshed = TodayPlanPresentation.rows(
        snapshotRows: [snapshot],
        livePlan: [plan],
        reminders: []
    )
    #expect(refreshed.first?.estimateMinutes == 45)
    #expect(refreshed.first?.declaredContext == .technical)
    #expect(DeclaredTaskContextResolver.taskType(declaredContext: .technical, title: "Write proposal") == "technical")
    #expect(DeclaredTaskContextResolver.taskType(declaredContext: nil, title: "Write proposal") == "write")

    let technical = ActiveCommitmentPresentation(task: snapshot)
    #expect(technical?.dashboardHeading.hasPrefix("TECHNICAL TASK · ACTIVE COMMITMENT") == true)
    #expect(technical?.menuStatus.hasPrefix("Technical task · Active") == true)
    #expect(technical?.accessibilitySummary.hasPrefix("Technical task. Write proposal.") == true)

    let general = TodayTaskRow(
        taskID: "local:user:general",
        title: "General task",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .low,
        state: .active,
        elapsedMinutes: 12
    )
    let generalPresentation = ActiveCommitmentPresentation(task: general)
    #expect(generalPresentation?.dashboardHeading == "ACTIVE COMMITMENT · OPEN-ENDED · 12 MIN TRACKED")
    #expect(generalPresentation?.menuStatus == "Active · Open-ended · 12 min tracked")
    #expect(generalPresentation?.accessibilitySummary.hasPrefix("General task. OPEN-ENDED SESSION.") == true)
}

private actor LocalTaskTestClient: LocalTaskMutationSubmitting {
    struct Submission: Equatable {
        let task: AgentLocalTask
        let addToToday: Bool
        let day: Date
    }

    private(set) var submissions: [Submission] = []
    private let failFirst: Bool

    init(failFirst: Bool) {
        self.failFirst = failFirst
    }

    func createLocalTask(_ task: AgentLocalTask, addToToday: Bool, day: Date) async throws -> AgentMutationReceipt {
        submissions.append(.init(task: task, addToToday: addToToday, day: day))
        if failFirst && submissions.count == 1 { throw LocalTaskTestError.expectedFailure }
        return .init(accepted: true, message: "Saved")
    }
}

private enum LocalTaskTestError: Error {
    case expectedFailure
}

private struct EmptyLocalTaskCalendar: CalendarAvailabilitySource {
    func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [ZoidCoachCore.CalendarCommitment] {
        []
    }
}

private func makeLocalTaskRouter(
    databaseURL: URL,
    reminders: ReminderSnapshotStore
) throws -> AgentMutationRouter {
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    return AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyLocalTaskCalendar()
        ),
        policyStore: try PolicyStore(databaseURL: databaseURL),
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL)
    )
}

private func temporaryLocalTaskDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-local-task-\(UUID().uuidString).sqlite")
}

private func removeLocalTaskDatabase(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
