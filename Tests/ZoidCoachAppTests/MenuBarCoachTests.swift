import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test func applicationComposesTodayAndCompactControlsFromOneRuntimeBoundary() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/ZoidCoachApp/ZoidCoachApp.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("let runtimeEnvironment = RuntimeEnvironment.current()"))
    #expect(source.contains("AppModel(runtimeEnvironment: runtimeEnvironment)"))
    #expect(source.contains("MenuBarCoachController(\n            runtimeEnvironment: runtimeEnvironment"))
    #expect(source.contains("MenuBarCoachingPauseController(\n            runtimeEnvironment: runtimeEnvironment"))
    #expect(source.contains("controller: menuBarCoach"))
    #expect(source.contains("pauseController: menuBarCoachingPause"))
}

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
    #expect(activeState.taskStatus == "Active · Open-ended · 12 min tracked")
    #expect(activeState.activeCommitment?.modeLabel == "OPEN-ENDED SESSION")
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

@Test func compactActiveTaskKeepsEssentialStateVisibleAndAccessible() throws {
    let dueDate = Date(timeIntervalSince1970: 1_800_003_600)
    let row = menuTask(
        id: "focus",
        title: "Prepare launch brief",
        state: .active,
        elapsedMinutes: 12,
        estimateMinutes: 45,
        dueDate: dueDate,
        urgency: .high,
        isMainObjective: true
    )
    let snapshot = menuSnapshot(
        rows: [row],
        activeTask: .init(taskID: row.taskID, startedAt: nil, elapsedMinutes: 12)
    )
    let state = MenuBarCoachState(snapshot: snapshot)

    #expect(state.compactTaskFacts.contains("Main objective"))
    #expect(state.compactTaskFacts.contains("45 min estimate"))
    #expect(state.compactTaskFacts.contains("High urgency"))
    #expect(state.compactTaskFacts.contains(
        "Due \(dueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    ))
    let summary = try #require(state.compactTaskAccessibilitySummary(at: dueDate))
    #expect(summary.contains("Prepare launch brief"))
    #expect(summary.contains("Active"))
    #expect(summary.contains("12 min tracked"))
    #expect(summary.contains("Main objective"))
    #expect(state.availableTaskActions == [.pause, .startBreak, .complete, .markBlocked, .openToday, .endWorkday])
    #expect(Set(state.availableTaskActions).count == state.availableTaskActions.count)
    #expect(state.availableTaskActions.map(\.accessibilityLabel) == [
        "Pause active task",
        "Start a 15 minute break",
        "Complete active task",
        "Mark task as blocked",
        "Open Today",
        "End the workday"
    ])
}

@Test func compactActiveElapsedTimeAdvancesFromTheLastConfirmedSnapshot() {
    let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let row = menuTask(id: "active", title: "Write proposal", state: .active, elapsedMinutes: 32)
    let state = MenuBarCoachState(
        snapshot: menuSnapshot(
            rows: [row],
            activeTask: .init(taskID: row.taskID, startedAt: confirmedAt.addingTimeInterval(-720), elapsedMinutes: 32)
        ),
        snapshotConfirmedAt: confirmedAt
    )

    #expect(state.taskStatus(at: confirmedAt) == "Active · Open-ended · 32 min tracked")
    #expect(state.taskStatus(at: confirmedAt.addingTimeInterval(125)) == "Active · Open-ended · 34 min tracked")
    #expect(state.taskStatus(at: confirmedAt.addingTimeInterval(-60)) == "Active · Open-ended · 32 min tracked")
}

@Test func compactStatusItemNeverLeaksThePrivateTaskTitle() {
    let privateTitle = "Confidential acquisition for Northwind"
    let row = menuTask(id: "private", title: privateTitle, state: .active)
    let state = MenuBarCoachState(snapshot: menuSnapshot(
        rows: [row],
        activeTask: .init(taskID: row.taskID, startedAt: nil, elapsedMinutes: 3)
    ))

    #expect(state.menuBarLabel == "A task is active")
    #expect(!state.menuBarLabel.contains(privateTitle))
    #expect(state.compactTaskAccessibilitySummary(at: Date())?.contains(privateTitle) == true)
}

@Test func compactPausedTaskHasOneTruthfulResumePathAndNoActiveOnlyActions() {
    let row = menuTask(
        id: "paused",
        title: "Write launch plan",
        state: .paused,
        elapsedMinutes: 17,
        pauseReason: .doneForNow
    )
    let state = MenuBarCoachState(snapshot: menuSnapshot(rows: [row]))

    #expect(state.availableTaskActions == [.resume, .markBlocked, .openToday])
    #expect(Set(state.availableTaskActions).count == state.availableTaskActions.count)
    #expect(!state.availableTaskActions.contains(.pause))
    #expect(!state.availableTaskActions.contains(.complete))
    #expect(state.taskStatus(at: Date(timeIntervalSince1970: 1_900_000_000)) == "Paused because you are done for now")
}

@Test func compactTaskFactsExposeLockedAndBlockedStateWithoutInventingIt() {
    let blocked = TodayTaskRow(
        taskID: "blocked",
        title: "Waiting for approval",
        estimateMinutes: 20,
        dueDate: nil,
        urgency: .medium,
        state: .paused,
        isLocked: true,
        blockedReason: "Client approval"
    )
    let state = MenuBarCoachState(snapshot: menuSnapshot(rows: [blocked]))

    #expect(state.compactTaskFacts.contains("Locked"))
    #expect(state.compactTaskFacts.contains("Blocked: Client approval"))
}

@Test func compactConfirmedBlockedTaskRemainsVisibleWithOnlyTruthfulActions() throws {
    let blocked = TodayTaskRow(
        taskID: "blocked",
        title: "Waiting for approval",
        estimateMinutes: 20,
        dueDate: nil,
        urgency: .medium,
        state: .blocked,
        isLocked: true,
        blockedReason: "Client approval"
    )
    let state = MenuBarCoachState(snapshot: menuSnapshot(rows: [blocked]))

    #expect(state.primaryTask?.taskID == blocked.taskID)
    #expect(state.tone == .attention)
    #expect(state.taskStatus(at: Date()) == "Blocked: Client approval")
    #expect(state.compactTaskFacts.contains("Blocked: Client approval"))
    #expect(state.availableTaskActions == [.openToday])
    #expect(try #require(state.compactTaskAccessibilitySummary(at: Date())).contains("Client approval"))
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
@Test func activeMenuTaskCompletesThroughTheSameDurableCommandBoundary() async {
    let activeRow = menuTask(id: "task", title: "Write proposal", state: .active, elapsedMinutes: 12)
    let active = menuSnapshot(
        rows: [activeRow],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 12)
    )
    let completed = menuSnapshot(rows: [
        menuTask(id: "task", title: "Write proposal", state: .completed, elapsedMinutes: 12)
    ])
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(active),
        applyResults: [.success(completed)]
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { active })

    await controller.refresh()
    await controller.apply(.complete, taskID: "task")

    #expect(controller.state.activeTask == nil)
    #expect(controller.state.primaryTask == nil)
    let commands = await client.commands
    #expect(commands.count == 1)
    #expect(commands.first?.0 == .complete)
    #expect(commands.first?.1 == "task")
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
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { ready })

    await controller.refresh()
    #expect(controller.state.recommendedTask?.taskID == "task")
    #expect(controller.syncPresentation == .confirmed)

    await controller.apply(.start, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage == nil)

    await controller.apply(.pauseDoneForNow, taskID: "task")
    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.errorMessage?.contains("last confirmed state") == true)
    #expect(controller.syncPresentation == .stale)

    let commands = await client.commands
    #expect(commands.map(\.0) == [.start, .pauseDoneForNow])
    #expect(commands.map(\.1) == ["task", "task"])
}

@MainActor
@Test func menuBarInitialRefreshFailureNeverClaimsThereIsNoActiveTask() async {
    let client = RecordingMenuBarTodayClient(
        fetchResult: .failure(MenuBarClientError.failed),
        applyResults: []
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { nil })

    #expect(controller.syncPresentation == .loading)
    await controller.refresh()

    #expect(controller.snapshot == nil)
    #expect(controller.syncPresentation == .unavailable)
    #expect(controller.errorMessage == "Task state is unavailable because Zoid 666 has not prepared a confirmed state yet. Open Today or Source Health, then refresh.")
}

@MainActor
@Test func compactMenuPreservesTodayTaskWhenItsOwnHelperRefreshFails() async {
    let active = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active, elapsedMinutes: 9)],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 9)
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .failure(MenuBarClientError.failed),
        applyResults: []
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { nil })

    controller.adoptLastKnownSnapshot(active)
    await controller.refresh()

    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.state.taskStatus == "Active · Open-ended · 9 min tracked")
    #expect(controller.syncPresentation == .stale)
    #expect(controller.errorMessage == "Today has not prepared a newer confirmed state. The last confirmed task state remains visible. Open Source Health, then refresh.")
}

@MainActor
@Test func failedMenuRefreshLeavesWorkHoursAllowanceAwaitingConfirmation() async {
    let gaming = GamingStatus(
        budgetMinutes: 30,
        usedMinutes: 20,
        unlockedRemainingMinutes: 10,
        nextUnlockReason: "Work-hours gaming is capped at 30 minutes.",
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: true)
    )
    let lastKnown = menuSnapshot(gaming: gaming)
    let controller = MenuBarCoachController(
        client: RecordingMenuBarTodayClient(
            fetchResult: .failure(MenuBarClientError.failed),
            applyResults: []
        ),
        loadTodaySnapshot: { nil }
    )

    controller.adoptLastKnownSnapshot(lastKnown)
    await controller.refresh()
    let presentation = MenuBarCoachState(
        snapshot: controller.snapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true),
        authoritativeGamingStatus: gaming,
        gamingStatusIsConfirmed: controller.syncPresentation == .confirmed
    ).gamingWorkHours

    #expect(controller.syncPresentation == .stale)
    #expect(presentation?.isAwaitingRefresh == true)
    #expect(presentation?.status == "Current allowance is awaiting a work-hours policy refresh")
}

@MainActor
@Test func compactMenuFallbackNeverOverwritesNewerControllerTruth() async {
    let staleReady = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .ready)]
    )
    let confirmedActive = menuSnapshot(
        rows: [menuTask(id: "task", title: "Task", state: .active, elapsedMinutes: 11)],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 11)
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(confirmedActive),
        applyResults: []
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { confirmedActive })

    await controller.refresh()
    controller.adoptLastKnownSnapshot(staleReady)

    #expect(controller.state.activeTask?.taskID == "task")
    #expect(controller.state.taskStatus == "Active · Open-ended · 11 min tracked")
    #expect(controller.syncPresentation == .confirmed)
    #expect(controller.errorMessage == nil)
}

@MainActor
@Test func activeTaskCanBeMarkedBlockedWithARequiredReasonAndConfirmedSnapshot() async {
    let activeRow = menuTask(id: "task", title: "Write proposal", state: .active)
    let active = menuSnapshot(
        rows: [activeRow],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 9)
    )
    let blocked = menuSnapshot(rows: [TodayTaskRow(
        taskID: "task",
        title: "Write proposal",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: .blocked,
        elapsedMinutes: 9,
        blockedReason: "Waiting for client approval"
    )])
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(active),
        applyResults: [],
        blockResults: [.success(blocked)]
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { active })

    await controller.refresh()
    await controller.block(taskID: "task", reason: "  Waiting for client approval  ")

    #expect(controller.snapshot?.taskRows.first?.state == .blocked)
    #expect(controller.snapshot?.taskRows.first?.blockedReason == "Waiting for client approval")
    #expect(controller.syncPresentation == .confirmed)
    #expect(controller.errorMessage == nil)
    let blockCommands = await client.blockCommands
    #expect(blockCommands.count == 1)
    #expect(blockCommands.first?.0 == "task")
    #expect(blockCommands.first?.1 == "Waiting for client approval")
}

@MainActor
@Test func blockActionRejectsInvalidReasonAndUnconfirmedAgentResponse() async {
    let activeRow = menuTask(id: "task", title: "Write proposal", state: .active)
    let active = menuSnapshot(
        rows: [activeRow],
        activeTask: .init(taskID: "task", startedAt: nil, elapsedMinutes: 9)
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(active),
        applyResults: [],
        blockResults: [.success(active)]
    )
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { active })

    await controller.refresh()
    await controller.block(taskID: "task", reason: "x")
    #expect(await client.blockCommands.isEmpty)
    #expect(controller.errorMessage?.contains("Nothing was changed") == true)

    await controller.block(taskID: "task", reason: "Waiting for client approval")
    #expect(controller.snapshot == active)
    #expect(controller.syncPresentation == .stale)
    #expect(controller.errorMessage?.contains("did not confirm") == true)
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
    let controller = MenuBarCoachController(client: client, loadTodaySnapshot: { active })

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
    let controller = MenuBarCoachController(
        client: client,
        loadTodaySnapshot: { first }
    )

    await controller.refresh()
    await controller.endWorkdayIfStillActive(taskID: "first")

    #expect(controller.state.activeTask?.taskID == "second")
    #expect(controller.errorMessage?.contains("Nothing was paused") == true)
    #expect(await client.commands.isEmpty)
}

@MainActor
@Test func menuBarStartsOnlyTheFreshRecommendedTaskAndConfirmsItBecameActive() async {
    let ready = menuSnapshot(
        rows: [menuTask(id: "focus", title: "Ship the review", state: .ready)],
        recommendation: .init(
            taskID: "focus",
            sentence: "Start Ship the review.",
            reasons: []
        )
    )
    let active = menuSnapshot(
        rows: [menuTask(id: "focus", title: "Ship the review", state: .active)],
        activeTask: .init(taskID: "focus", startedAt: Date(), elapsedMinutes: 0)
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(ready),
        applyResults: [.success(active)]
    )
    let controller = MenuBarCoachController(client: client)

    await controller.startRecommendedTaskIfStillReady(taskID: "focus")

    #expect(controller.state.activeTask?.taskID == "focus")
    #expect(controller.errorMessage == nil)
    let commands = await client.commands
    #expect(commands.count == 1)
    #expect(commands.first?.0 == .start)
    #expect(commands.first?.1 == "focus")
    #expect(await client.fetchCount == 1)
}

@MainActor
@Test func menuBarRefusesAStartAfterTheRecommendationChanges() async {
    let replacement = menuSnapshot(
        rows: [menuTask(id: "replacement", title: "New priority", state: .ready)],
        recommendation: .init(
            taskID: "replacement",
            sentence: "Start New priority.",
            reasons: []
        )
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(replacement),
        applyResults: []
    )
    let controller = MenuBarCoachController(client: client)

    await controller.startRecommendedTaskIfStillReady(taskID: "stale")

    #expect(controller.state.recommendedTask?.taskID == "replacement")
    #expect(controller.errorMessage?.contains("Nothing was started") == true)
    #expect(await client.commands.isEmpty)
}

@MainActor
@Test func menuBarRejectsAnUnconfirmedStartResultWithoutReplacingFreshState() async {
    let ready = menuSnapshot(
        rows: [menuTask(id: "focus", title: "Ship the review", state: .ready)],
        recommendation: .init(
            taskID: "focus",
            sentence: "Start Ship the review.",
            reasons: []
        )
    )
    let client = RecordingMenuBarTodayClient(
        fetchResult: .success(ready),
        applyResults: [.success(ready)]
    )
    let controller = MenuBarCoachController(client: client)

    await controller.startRecommendedTaskIfStillReady(taskID: "focus")

    #expect(controller.state.recommendedTask?.taskID == "focus")
    #expect(controller.state.activeTask == nil)
    #expect(controller.errorMessage?.contains("did not confirm") == true)
    #expect(await client.commands.count == 1)
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
    let agent = try TodayDashboardAgent(databaseURL: databaseURL)
    let initialSnapshot = try agent.snapshot(now: now)
    let client = AgentMenuBarTodayClient(
        agent: agent,
        now: now
    )
    let controller = MenuBarCoachController(
        client: client,
        loadTodaySnapshot: { initialSnapshot }
    )

    await controller.refresh()
    await controller.startRecommendedTaskIfStillReady(taskID: "focus")
    #expect(controller.state.activeTask?.taskID == "focus")
    #expect(controller.state.activeCommitment?.modeLabel == "OPEN-ENDED SESSION")
    #expect(controller.state.taskStatus == "Active · Open-ended · 0 min tracked")
    let activeAfterRestart = try TodayDashboardAgent(databaseURL: databaseURL)
        .snapshot(now: now.addingTimeInterval(90))
    let restartedActiveRow = try #require(activeAfterRestart.taskRows.first { $0.taskID == "focus" })
    #expect(restartedActiveRow.state == .active)
    #expect(ActiveCommitmentPresentation(task: restartedActiveRow)?.modeLabel == "OPEN-ENDED SESSION")
    #expect(MenuBarCoachState(snapshot: activeAfterRestart).activeTask?.taskID == "focus")
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

    let relaunchedSnapshot = try TodaySnapshotStore(
        databaseURL: databaseURL,
        readOnly: true
    ).load(for: now.addingTimeInterval(360))
    let relaunchedController = MenuBarCoachController(
        client: AgentMenuBarTodayClient(
            agent: try TodayDashboardAgent(databaseURL: databaseURL),
            now: now.addingTimeInterval(360)
        ),
        loadTodaySnapshot: { relaunchedSnapshot }
    )
    await relaunchedController.refresh()
    #expect(relaunchedController.state.primaryTask?.taskID == "focus")
    #expect(relaunchedController.state.availableTaskActions == [.resume, .markBlocked, .openToday])
    #expect(relaunchedController.state.taskStatus == "Workday ended · Tracked time is saved")
}

@MainActor
@Test func compactMenuReopensAnUnplannedPausedTaskWithResume() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-menu-unplanned-pause-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(id: "focus", title: "Verify the ready-state journey", dueDate: startedAt, priority: 9),
        ReminderSourceSnapshot(id: "queued", title: "Leave this queued", dueDate: startedAt, priority: 0)
    ])
    let agent = try TodayDashboardAgent(databaseURL: databaseURL)

    let active = try agent.startUnplannedTask("focus", now: startedAt)
    #expect(active.activeTask?.taskID == "focus")
    #expect(active.taskRows.first(where: { $0.taskID == "focus" })?.state == .active)

    let paused = try agent.apply(
        .pauseDoneForNow,
        taskID: "focus",
        now: startedAt.addingTimeInterval(60)
    )
    #expect(paused.taskRows.first(where: { $0.taskID == "focus" })?.state == .paused)

    let reopenedSnapshot = try TodaySnapshotStore(
        databaseURL: databaseURL,
        readOnly: true
    ).load(for: startedAt.addingTimeInterval(120))
    let reopenedController = MenuBarCoachController(
        client: AgentMenuBarTodayClient(
            agent: try TodayDashboardAgent(databaseURL: databaseURL),
            now: startedAt.addingTimeInterval(120)
        ),
        loadTodaySnapshot: { reopenedSnapshot }
    )
    await reopenedController.refresh()

    #expect(reopenedController.state.pausedTask?.taskID == "focus")
    #expect(reopenedController.state.primaryTask?.title == "Verify the ready-state journey")
    #expect(reopenedController.state.availableTaskActions == [.resume, .markBlocked, .openToday])
    #expect(reopenedController.state.taskStatus == "Paused because you are done for now")
    #expect(reopenedController.snapshot?.taskRows.contains(where: { $0.taskID == "queued" }) == false)
    #expect(reopenedController.snapshot?.unplannedReminders?.contains(where: { $0.reminderID == "queued" }) == true)
}

private actor RecordingMenuBarTodayClient: MenuBarTodayClient {
    let fetchResult: Result<TodaySnapshot, Error>
    var applyResults: [Result<TodaySnapshot, Error>]
    var blockResults: [Result<TodaySnapshot, Error>]
    private(set) var commands: [(TaskActivityCommand, String)] = []
    private(set) var blockCommands: [(String, String)] = []
    private(set) var fetchCount = 0

    init(
        fetchResult: Result<TodaySnapshot, Error>,
        applyResults: [Result<TodaySnapshot, Error>],
        blockResults: [Result<TodaySnapshot, Error>] = []
    ) {
        self.fetchResult = fetchResult
        self.applyResults = applyResults
        self.blockResults = blockResults
    }

    func fetchTodaySnapshot() async throws -> TodaySnapshot {
        fetchCount += 1
        return try fetchResult.get()
    }

    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot {
        commands.append((command, taskID))
        guard !applyResults.isEmpty else { throw MenuBarClientError.failed }
        return try applyResults.removeFirst().get()
    }

    func blockTask(taskID: String, reason: String) async throws -> TodaySnapshot {
        blockCommands.append((taskID, reason))
        guard !blockResults.isEmpty else { throw MenuBarClientError.failed }
        return try blockResults.removeFirst().get()
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

    func blockTask(taskID: String, reason: String) throws -> TodaySnapshot {
        now = now.addingTimeInterval(60)
        return try agent.apply(.block, taskID: taskID, blockedReason: reason, now: now)
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

    func blockTask(taskID: String, reason: String) throws -> TodaySnapshot {
        commands.append((.block, taskID))
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
    sprint: SprintSnapshot? = nil,
    isOptional: Bool = false,
    estimateMinutes: Int = 30,
    dueDate: Date? = nil,
    urgency: TaskUrgency = .medium,
    isMainObjective: Bool = false
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: title,
        estimateMinutes: estimateMinutes,
        dueDate: dueDate,
        urgency: urgency,
        state: state,
        elapsedMinutes: elapsedMinutes,
        latestPauseReason: pauseReason,
        acceptedBreak: acceptedBreak,
        sprint: sprint,
        isMainObjective: isMainObjective,
        isOptional: isOptional
    )
}

private func menuSnapshot(
    rows: [TodayTaskRow] = [],
    activeTask: ActiveTaskSnapshot? = nil,
    recommendation: NextTaskRecommendation = .init(taskID: nil, sentence: "Nothing ready", reasons: []),
    sources: [SourceFreshnessSnapshot] = [],
    gaming: GamingStatus = GamingStatus(
        budgetMinutes: 60,
        usedMinutes: 0,
        unlockedRemainingMinutes: 0,
        nextUnlockReason: "Finish one priority task",
        confidenceIsLimited: false
    )
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
        gaming: gaming,
        sourceFreshnessExplanation: "Fixture sources",
        sources: sources
    )
}
