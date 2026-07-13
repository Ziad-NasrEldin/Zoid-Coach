import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test func menuBarStateDistinguishesNeutralAttentionActiveAndPaused() {
    #expect(MenuBarCoachState(snapshot: nil).tone == .neutral)

    let healthy = menuSnapshot(sources: [
        SourceFreshnessSnapshot(sourceID: "agent", state: "running", detail: "Agent is current", lastUpdatedAt: nil)
    ])
    #expect(MenuBarCoachState(snapshot: healthy).tone == .neutral)

    let attention = menuSnapshot(sources: [
        SourceFreshnessSnapshot(sourceID: "screenwatch", state: "limited", detail: "No recent activity", lastUpdatedAt: nil)
    ])
    let attentionState = MenuBarCoachState(snapshot: attention)
    #expect(attentionState.tone == .attention)
    #expect(attentionState.attentionDetail == "screenwatch: No recent activity")

    let activeRow = menuTask(id: "active", title: "Write proposal", state: .active, elapsedMinutes: 12)
    let active = menuSnapshot(rows: [activeRow], activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 12), sources: attention.sources ?? [])
    let activeState = MenuBarCoachState(snapshot: active)
    #expect(activeState.tone == .active)
    #expect(activeState.primaryTask?.title == "Write proposal")
    #expect(activeState.taskStatus == "Active · 12 min tracked")
    #expect(activeState.canStartBreak)
    #expect(activeState.canEndWorkday)

    let paused = menuSnapshot(rows: [menuTask(id: "paused", title: "Review budget", state: .paused, pauseReason: .doneForNow)])
    let pausedState = MenuBarCoachState(snapshot: paused)
    #expect(pausedState.tone == .paused)
    #expect(pausedState.taskStatus == "Paused because you are done for now")
    #expect(!pausedState.canStartBreak)
    #expect(!pausedState.canEndWorkday)

    let coachingPausedState = MenuBarCoachState(snapshot: active, coachingIsPaused: true)
    #expect(coachingPausedState.tone == .coachingPaused)
    #expect(coachingPausedState.tone.label == "Coaching is paused")
    #expect(coachingPausedState.primaryTask?.title == "Write proposal")
}

@Test func unavailableNotificationsExposeAStableDecisionBadgeWithoutRemovingTaskControls() {
    let active = menuSnapshot(
        rows: [menuTask(id: "active", title: "Write proposal", state: .active)],
        activeTask: .init(taskID: "active", startedAt: nil, elapsedMinutes: 8)
    )

    let fallback = MenuBarCoachState(
        snapshot: active,
        unresolvedPromptCount: 2,
        notificationsUnavailable: true
    )

    #expect(fallback.tone == .active)
    #expect(fallback.menuBarSymbol == "exclamationmark.bubble.fill")
    #expect(fallback.menuBarLabel == "2 decisions are waiting in Today")
    #expect(fallback.notificationFallbackDetail == "Notifications are unavailable. 2 decisions waiting in Today. Task controls remain available here.")
    #expect(fallback.activeTask?.taskID == "active")
    #expect(fallback.canStartBreak)
    #expect(fallback.canEndWorkday)

    let healthyDelivery = MenuBarCoachState(
        snapshot: active,
        unresolvedPromptCount: 2,
        notificationsUnavailable: false
    )
    #expect(healthyDelivery.menuBarSymbol == MenuBarCoachTone.active.symbol)
    #expect(healthyDelivery.notificationFallbackDetail == nil)

    let noDecision = MenuBarCoachState(
        snapshot: active,
        unresolvedPromptCount: 0,
        notificationsUnavailable: true
    )
    #expect(noDecision.menuBarSymbol == MenuBarCoachTone.active.symbol)
    #expect(noDecision.notificationFallbackDetail == nil)
}

@MainActor
@Test func menuBarCoachingPauseRefreshesAndPersistsOnlyThePauseSetting() async throws {
    let initial = VersionedUserPolicy(
        version: 7,
        policy: .defaults(timeZoneIdentifier: "Africa/Cairo"),
        createdAtUTC: Date(timeIntervalSince1970: 1_800_000_000),
        isActive: true
    )
    let client = RecordingMenuBarCoachingPauseClient(current: initial)
    let controller = MenuBarCoachingPauseController(
        client: client,
        makeRequestID: { "system-policy-v1:menu-bar-coaching-pause:test-pause" }
    )

    await controller.refresh()
    #expect(!controller.isPaused)
    #expect(controller.policyVersion == 7)

    await controller.setPaused(true)

    #expect(controller.isPaused)
    #expect(controller.policyVersion == 8)
    #expect(controller.errorMessage == nil)
    #expect(controller.statusMessage?.contains("Task tracking and Today remain available") == true)

    let pauseRequest = try #require(await client.requests.first)
    #expect(pauseRequest.requestID == "system-policy-v1:menu-bar-coaching-pause:test-pause")
    #expect(pauseRequest.expectedVersion == 7)
    #expect(pauseRequest.origin == .system(component: "menu-bar-coaching-pause"))
    #expect(pauseRequest.policy.automationPause.isRequested)
    #expect(
        pauseRequest.policy.replacingAutomationPause(initial.policy.automationPause)
            == initial.policy
    )

    await controller.setPaused(false)

    #expect(!controller.isPaused)
    #expect(controller.policyVersion == 9)
    #expect(controller.statusMessage?.contains("Coaching resumed") == true)
    let requests = await client.requests
    #expect(requests.count == 2)
    #expect(requests[1].expectedVersion == 8)
    #expect(!requests[1].policy.automationPause.isRequested)
}

@MainActor
@Test func menuBarCoachingPauseRejectsAnUnconfirmedMutation() async {
    let initial = VersionedUserPolicy(
        version: 3,
        policy: .defaults(timeZoneIdentifier: "UTC"),
        createdAtUTC: Date(timeIntervalSince1970: 1_800_000_000),
        isActive: true
    )
    let client = RecordingMenuBarCoachingPauseClient(current: initial, returnsInvalidReceipt: true)
    let controller = MenuBarCoachingPauseController(client: client)

    await controller.refresh()
    await controller.setPaused(true)

    #expect(!controller.isPaused)
    #expect(controller.policyVersion == 3)
    #expect(controller.statusMessage == nil)
    #expect(controller.errorMessage?.contains("did not confirm") == true)
}

@Test func menuBarExplainsEndOfWorkdayWithoutLosingThePausedTask() {
    let ended = menuSnapshot(rows: [
        menuTask(
            id: "ended",
            title: "Finish proposal",
            state: .paused,
            elapsedMinutes: 38,
            pauseReason: .endingWorkday
        )
    ])

    let state = MenuBarCoachState(snapshot: ended)

    #expect(state.tone == .paused)
    #expect(state.workdayHasEnded)
    #expect(state.primaryTask?.title == "Finish proposal")
    #expect(state.primaryTask?.elapsedMinutes == 38)
    #expect(state.taskStatus == "Workday ended · Tracked time is saved")
}

@Test func menuBarChoosesExplicitRecommendationBeforeFallbackReadyTask() {
    let rows = [
        menuTask(id: "fallback", title: "Fallback", state: .ready),
        menuTask(id: "recommended", title: "Recommended", state: .ready)
    ]
    let snapshot = menuSnapshot(
        rows: rows,
        recommendation: NextTaskRecommendation(
            taskID: "recommended",
            sentence: "Start Recommended",
            reasons: [.mainObjective]
        )
    )

    #expect(MenuBarCoachState(snapshot: snapshot).recommendedTask?.taskID == "recommended")
}

@Test func menuBarDoesNotOfferOptionalOrUnavailableRecommendationAsFallback() {
    let rows = [
        menuTask(id: "optional", title: "Optional", state: .ready, isOptional: true),
        menuTask(id: "blocked", title: "Blocked", state: .blocked)
    ]
    let snapshot = menuSnapshot(
        rows: rows,
        recommendation: NextTaskRecommendation(taskID: "missing", sentence: "Unavailable", reasons: [])
    )

    #expect(MenuBarCoachState(snapshot: snapshot).recommendedTask == nil)
}

@MainActor
@Test func menuBarControllerRefreshesAppliesAndPreservesLastConfirmedStateOnFailure() async {
    let ready = menuSnapshot(rows: [menuTask(id: "task", title: "Task", state: .ready)])
    let active = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active)],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 0)
    )
    let client = RecordingMenuBarTodayClient(fetchResult: .success(ready), applyResults: [.success(active), .failure(MenuBarClientError.failed)])
    let controller = MenuBarCoachController(client: client)

    await controller.refresh()
    #expect(controller.state.recommendedTask?.taskID == "task")

    await controller.apply(.start, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage == nil)

    await controller.apply(.pauseDoneForNow, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage?.contains("last confirmed state") == true)

    let commands = await client.commands
    #expect(commands.map(\.0) == [.start, .pauseDoneForNow])
    #expect(commands.map(\.1) == ["task", "task"])
}

@MainActor
@Test func menuBarControllerRunsBreakResumeAndConfirmedEndWorkdayJourney() async {
    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let active = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active, elapsedMinutes: 12)],
        activeTask: .init(taskID: "task", startedAt: startedAt, elapsedMinutes: 12)
    )
    let onBreak = menuSnapshot(rows: [
        menuTask(
            id: "task",
            title: "Task",
            state: .paused,
            elapsedMinutes: 12,
            pauseReason: .break,
            acceptedBreak: AcceptedBreakSnapshot(startedAt: startedAt)
        )
    ])
    let resumed = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active, elapsedMinutes: 12)],
        activeTask: .init(taskID: "task", startedAt: startedAt, elapsedMinutes: 12)
    )
    let ended = menuSnapshot(rows: [
        menuTask(id: "task", title: "Task", state: .paused, elapsedMinutes: 12, pauseReason: .endingWorkday)
    ])
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(active),
        applyResults: [.success(onBreak), .success(resumed), .success(ended)]
    )
    let controller = MenuBarCoachController(client: client)

    await controller.refresh()
    await controller.apply(.pauseForBreak, taskID: "task")
    #expect(controller.state.pausedTask?.acceptedBreak != nil)
    #expect(controller.state.taskStatus(at: startedAt) == "Accepted break · 15 min left")

    await controller.apply(.resume, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")

    await controller.apply(.pauseForEndOfDay, taskID: "task")
    #expect(controller.state.workdayHasEnded)
    #expect(controller.state.taskStatus == "Workday ended · Tracked time is saved")

    let commands = await client.commands
    #expect(commands.map(\.0) == [.pauseForBreak, .resume, .pauseForEndOfDay])
    #expect(commands.allSatisfy { $0.1 == "task" })
}

@MainActor
@Test func endWorkdayConfirmationDoesNothingWhenTheActiveTaskChanged() async {
    let first = menuSnapshot(
        rows: [menuTask(id: "first", title: "First", state: .active)],
        activeTask: .init(taskID: "first", startedAt: Date(), elapsedMinutes: 2)
    )
    let second = menuSnapshot(
        rows: [menuTask(id: "second", title: "Second", state: .active)],
        activeTask: .init(taskID: "second", startedAt: Date(), elapsedMinutes: 1)
    )
    let client = SwitchingMenuBarTodayClient(snapshots: [first, second])
    let controller = MenuBarCoachController(client: client)

    await controller.refresh()
    await controller.endWorkdayIfStillActive(taskID: "first")

    #expect(controller.state.activeTask?.taskID == "second")
    #expect(controller.errorMessage?.contains("Nothing was paused") == true)
    #expect(await client.commands.isEmpty)
}

@MainActor
@Test func menuBarBreakAndEndWorkdayPersistThroughTheCanonicalAgent() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-menu-workday-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let now = Date()
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "focus", title: "Ship the review", dueDate: now, priority: 9)
    ])
    let plans = try AutonomousPlanStore(databaseURL: databaseURL)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(
                    taskID: "focus",
                    title: "Ship the review",
                    rank: 1,
                    estimateMinutes: 45,
                    reason: "Main objective",
                    score: 100
                )
            ],
            mainObjectiveTaskID: "focus",
            plannedFocusMinutes: 45,
            availableFocusMinutes: 120
        ),
        for: now
    )
    let client = AgentMenuBarTodayClient(
        agent: try TodayDashboardAgent(databaseURL: databaseURL),
        now: now
    )
    let controller = MenuBarCoachController(client: client)

    await controller.refresh()
    await controller.apply(.start, taskID: "focus")
    await controller.apply(.pauseForBreak, taskID: "focus")
    #expect(controller.state.pausedTask?.acceptedBreak != nil)

    await controller.apply(.resume, taskID: "focus")
    await controller.apply(.pauseForEndOfDay, taskID: "focus")
    #expect(controller.state.workdayHasEnded)
    #expect(controller.state.primaryTask?.title == "Ship the review")

    let restored = try TodayDashboardAgent(databaseURL: databaseURL)
        .snapshot(now: now.addingTimeInterval(300))
    let restoredTask = try #require(restored.taskRows.first { $0.taskID == "focus" })
    #expect(restoredTask.state == .paused)
    #expect(restoredTask.latestPauseReason == .endingWorkday)
    #expect(restoredTask.acceptedBreak == nil)
}

private actor RecordingMenuBarTodayClient: MenuBarTodayClient {
    let fetchResult: Result<TodaySnapshot, Error>
    var applyResults: [Result<TodaySnapshot, Error>]
    private(set) var commands: [(TaskActivityCommand, String)] = []

    init(fetchResult: Result<TodaySnapshot, Error>, applyResults: [Result<TodaySnapshot, Error>]) {
        self.fetchResult = fetchResult
        self.applyResults = applyResults
    }

    func fetchTodaySnapshot() async throws -> TodaySnapshot { try fetchResult.get() }

    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot {
        commands.append((command, taskID))
        guard !applyResults.isEmpty else { throw MenuBarClientError.failed }
        return try applyResults.removeFirst().get()
    }
}

private actor RecordingMenuBarCoachingPauseClient: MenuBarCoachingPauseClient {
    var current: VersionedUserPolicy
    let returnsInvalidReceipt: Bool
    private(set) var requests: [PolicyMutationRequest] = []

    init(current: VersionedUserPolicy, returnsInvalidReceipt: Bool = false) {
        self.current = current
        self.returnsInvalidReceipt = returnsInvalidReceipt
    }

    func loadCurrentPolicy() -> VersionedUserPolicy { current }

    func savePolicyMutation(_ request: PolicyMutationRequest) throws -> AgentMutationReceipt {
        requests.append(request)
        if returnsInvalidReceipt {
            return AgentMutationReceipt(accepted: true, message: "Missing durable receipt")
        }

        let resultingVersion = current.version + 1
        let receipt = PolicyMutationReceipt(
            requestID: request.requestID,
            payloadDigest: try PolicyMutationRequest.canonicalPayloadDigest(for: request.policy),
            expectedVersion: request.expectedVersion,
            resultingVersion: resultingVersion,
            origin: request.origin,
            replayed: false
        )
        current = VersionedUserPolicy(
            version: resultingVersion,
            policy: request.policy,
            createdAtUTC: Date(timeIntervalSince1970: TimeInterval(resultingVersion)),
            isActive: true
        )
        return AgentMutationReceipt(
            accepted: true,
            message: "Saved",
            policyVersion: resultingVersion,
            policyMutationReceipt: receipt
        )
    }
}

private actor AgentMenuBarTodayClient: MenuBarTodayClient {
    let agent: TodayDashboardAgent
    var now: Date

    init(agent: TodayDashboardAgent, now: Date) {
        self.agent = agent
        self.now = now
    }

    func fetchTodaySnapshot() throws -> TodaySnapshot {
        try agent.snapshot(now: now)
    }

    func apply(_ command: TaskActivityCommand, taskID: String) throws -> TodaySnapshot {
        now = now.addingTimeInterval(60)
        return try agent.apply(command, taskID: taskID, now: now)
    }
}

private actor SwitchingMenuBarTodayClient: MenuBarTodayClient {
    var snapshots: [TodaySnapshot]
    var commands: [(TaskActivityCommand, String)] = []

    init(snapshots: [TodaySnapshot]) {
        self.snapshots = snapshots
    }

    func fetchTodaySnapshot() throws -> TodaySnapshot {
        if snapshots.count > 1 { return snapshots.removeFirst() }
        return snapshots[0]
    }

    func apply(_ command: TaskActivityCommand, taskID: String) throws -> TodaySnapshot {
        commands.append((command, taskID))
        return snapshots[0]
    }
}

private enum MenuBarClientError: Error { case failed }

private func menuTask(
    id: String,
    title: String,
    state: TaskExecutionState,
    elapsedMinutes: Int = 0,
    pauseReason: TaskPauseReason? = nil,
    acceptedBreak: AcceptedBreakSnapshot? = nil,
    isOptional: Bool = false
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: title,
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: state,
        elapsedMinutes: elapsedMinutes,
        latestPauseReason: pauseReason,
        acceptedBreak: acceptedBreak,
        isOptional: isOptional
    )
}

private func menuSnapshot(
    rows: [TodayTaskRow] = [],
    activeTask: ActiveTaskSnapshot? = nil,
    recommendation: NextTaskRecommendation = .init(taskID: nil, sentence: "Nothing ready", reasons: []),
    sources: [SourceFreshnessSnapshot] = []
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: rows.first(where: \.isMainObjective)?.title,
        taskRows: rows,
        activeTask: activeTask,
        recommendation: recommendation,
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(isLimited: sources.contains { $0.state == "limited" }, explanation: "Fixture coverage", lastObservationAt: nil),
        gaming: GamingStatus(budgetMinutes: 60, usedMinutes: 0, unlockedRemainingMinutes: 0, nextUnlockReason: "Finish one priority task", confidenceIsLimited: false),
        sourceFreshnessExplanation: "Fixture sources",
        sources: sources
    )
}
