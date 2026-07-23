import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func meetingPromptResponseEnqueuesExactlyOneConfirmedMeetingActionAcrossSurfaces() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-prompt-effect-\(UUID().uuidString)", isDirectory: true)
    let dayDirectory = root.appendingPathComponent("2026-07-10", isDirectory: true)
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let line = "{\"t\":\"09-00-00\",\"epoch\":1783663200,\"app\":\"WhatsApp\",\"window\":\"Sarah\",\"url\":\"\",\"img\":true}\n"
    try Data(line.utf8).write(to: dayDirectory.appendingPathComponent("log.jsonl"))
    try Data([1, 2, 3]).write(to: dayDirectory.appendingPathComponent("09-00-00.jpg"))
    let archive = try ScreenwatchArchive(databaseURL: databaseURL)
    let observedAt = Date(timeIntervalSince1970: 1_783_663_200)
    _ = try archive.ingestToday(from: root, now: observedAt)
    let ocr = ScreenshotOCRResult(blocks: [
        OCRTextBlock(text: "Meeting tomorrow at 3 pm for 30 minutes", confidence: 0.95, boundingBox: NormalizedBoundingBox(x: 0, y: 0, width: 1, height: 1), localeHint: "en")
    ])
    _ = try await archive.analyzePendingWhatsAppScreenshots(
        authorization: promptScreenshotAnalysis(at: observedAt),
        using: PromptEffectRecognizer(result: ocr),
        cipher: try LocalEvidenceCipher(keyData: Data(repeating: 9, count: 32))
    )
    let candidateValue = try archive.unresolvedMeetingCandidates().first
    let candidate = try #require(candidateValue)
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "meeting:\(candidate.id)",
        type: "MEETING_CANDIDATE",
        title: candidate.title,
        summary: "Confirm meeting",
        actions: [PromptAction(kind: .addMeeting, title: "Add")],
        payload: ["candidateID": candidate.id]
    )).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .addMeeting)
    let first = try promptStore.respond(promptID: episode.id, action: .addMeeting, actionToken: token, surface: .notification)
    let second = try promptStore.respond(promptID: episode.id, action: .addMeeting, actionToken: token, surface: .dashboard)
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let router = PromptResponseEffectRouter(outbox: outbox, meetingArchive: archive)

    let firstEffect = try router.apply(first)
    let secondEffect = try router.apply(second)

    #expect(firstEffect != .none)
    #expect(secondEffect == .none)
    #expect(try outbox.recentCommands().filter { $0.type == .createConfirmedMeeting }.count == 1)
    #expect(try archive.meetingCandidate(id: candidate.id)?.state == "accepted")
}

private func promptScreenshotAnalysis(at now: Date) -> ScreenshotAnalysisAuthorization {
    ScreenshotAnalysisAuthorization(
        consentEnabled: true,
        canMateriallyChangeIntervention: true,
        resourceConstrained: false,
        rawScreenshotRetentionDays: 30,
        now: now
    )
}

private struct PromptEffectRecognizer: ScreenshotTextRecognizing {
    let result: ScreenshotOCRResult
    func recognize(in imageURL: URL) async throws -> ScreenshotOCRResult { result }
}

@Test
func editMeetingResponseRoutesCandidateIntoTheDashboardEditorQueue() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-prompt-edit-\(UUID().uuidString)", isDirectory: true)
    let dayDirectory = root.appendingPathComponent("2026-07-10", isDirectory: true)
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let line = "{\"t\":\"09-00-00\",\"epoch\":1783663200,\"app\":\"WhatsApp\",\"window\":\"Sarah\",\"url\":\"\",\"img\":true}\n"
    try Data(line.utf8).write(to: dayDirectory.appendingPathComponent("log.jsonl"))
    try Data([1, 2, 3]).write(to: dayDirectory.appendingPathComponent("09-00-00.jpg"))
    let archive = try ScreenwatchArchive(databaseURL: databaseURL)
    let observedAt = Date(timeIntervalSince1970: 1_783_663_200)
    _ = try archive.ingestToday(from: root, now: observedAt)
    let ocr = ScreenshotOCRResult(blocks: [
        OCRTextBlock(text: "Meeting tomorrow at 3 pm", confidence: 0.95, boundingBox: NormalizedBoundingBox(x: 0, y: 0, width: 1, height: 1), localeHint: "en")
    ])
    _ = try await archive.analyzePendingWhatsAppScreenshots(
        authorization: promptScreenshotAnalysis(at: observedAt),
        using: PromptEffectRecognizer(result: ocr),
        cipher: try LocalEvidenceCipher(keyData: Data(repeating: 4, count: 32))
    )
    let candidate = try #require(archive.unresolvedMeetingCandidates().first)
    let promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { observedAt })
    let episode = try promptStore.enqueue(MeetingPromptBuilder.draft(
        for: candidate,
        calendarDestination: "Work",
        assessment: .clear
    )).episode
    let response = try promptStore.respond(
        promptID: episode.id,
        action: .editMeeting,
        actionToken: PromptResponseToken.make(promptID: episode.id, action: .editMeeting),
        surface: .notification
    )
    let router = PromptResponseEffectRouter(
        outbox: try ActionOutboxStore(databaseURL: databaseURL),
        meetingArchive: archive,
        promptStore: promptStore
    )

    #expect(try router.apply(response) == .meetingEditRequested(candidateID: candidate.id))
    #expect(try archive.unresolvedMeetingCandidates().first?.state == "edit_requested")
}

@Test
func acceptingAPlanDurablyQueuesItsApprovalScheduleRequest() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-plan-approval-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "plan-ready:2026-07-11",
        type: "PLAN_READY",
        title: "Tomorrow's plan is ready",
        summary: "Review the commitments",
        actions: [PromptAction(kind: .acceptPlan, title: "Accept")],
        payload: ["localDay": "2026-07-11"]
    )).episode
    let response = try promptStore.respond(
        promptID: episode.id,
        action: .acceptPlan,
        actionToken: PromptResponseToken.make(promptID: episode.id, action: .acceptPlan),
        surface: .notification
    )
    let requests = try PlanScheduleRequestStore(databaseURL: databaseURL)
    let router = PromptResponseEffectRouter(
        outbox: try ActionOutboxStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduleRequests: requests,
        promptStore: promptStore
    )

    #expect(try router.apply(response) == .planScheduleQueued(dayKey: "2026-07-11"))
    let pendingRequest = try requests.claimNext()
    let request = try #require(pendingRequest)
    #expect(request.promptID == episode.id)
    #expect(request.dayKey == "2026-07-11")
    #expect(try promptStore.pendingEffects().isEmpty)
}

@Test
func gamingPromptReturnActionStartsTheNamedTaskExactlyOnce() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-return-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let observedAt = Date(timeIntervalSince1970: 1_784_000_000)
    let promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { observedAt })
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "gaming-drift:2026-07-13:1783990000",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Ready for an easy return?",
        summary: "Gaming was observed while the proposal remains unfinished.",
        actions: [PromptAction(kind: .returnToActiveTask, title: "Return to proposal")],
        payload: ["taskID": "priority-1"]
    )).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .returnToActiveTask)
    let first = try promptStore.respond(
        promptID: episode.id,
        action: .returnToActiveTask,
        actionToken: token,
        surface: .notification
    )
    let replay = try promptStore.respond(
        promptID: episode.id,
        action: .returnToActiveTask,
        actionToken: token,
        surface: .dashboard
    )
    let execution = try TaskExecutionStore(databaseURL: databaseURL)
    let router = PromptResponseEffectRouter(
        outbox: try ActionOutboxStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        promptStore: promptStore,
        taskExecution: execution
    )

    #expect(try router.apply(first) == .coachingTaskStarted(taskID: "priority-1"))
    #expect(try router.apply(replay) == .none)
    #expect(try execution.snapshot(for: ["priority-1"], now: observedAt)["priority-1"]?.state == .active)
}

@Test
func gamingPromptBreakActionPausesTheActiveTaskExactlyOnce() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-break-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let observedAt = Date(timeIntervalSince1970: 1_784_000_000)
    let execution = try TaskExecutionStore(databaseURL: databaseURL)
    try execution.apply(.start, taskID: "active-1", at: observedAt.addingTimeInterval(-600))
    let promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { observedAt })
    let episode = try promptStore.enqueue(PromptDraft(
        decisionKey: "gaming-drift:2026-07-13:1783990000",
        type: PromptNotificationCategory.gamingDrift.rawValue,
        title: "Is this gaming intentional?",
        summary: "Gaming was observed while active work remains unfinished.",
        actions: [PromptAction(kind: .startBreak, title: "Take a break")],
        payload: ["taskID": "priority-1"]
    )).episode
    let token = PromptResponseToken.make(promptID: episode.id, action: .startBreak)
    let first = try promptStore.respond(
        promptID: episode.id,
        action: .startBreak,
        actionToken: token,
        surface: .notification
    )
    let replay = try promptStore.respond(
        promptID: episode.id,
        action: .startBreak,
        actionToken: token,
        surface: .dashboard
    )
    let router = PromptResponseEffectRouter(
        outbox: try ActionOutboxStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        promptStore: promptStore,
        taskExecution: execution
    )

    #expect(try router.apply(first) == .coachingBreakStarted(taskID: "active-1"))
    #expect(try router.apply(replay) == .none)
    let snapshot = try execution.snapshot(for: ["active-1"], now: observedAt)["active-1"]
    #expect(snapshot?.state == .paused)
    #expect(snapshot?.latestPauseReason == .break)
    #expect(try execution.activeTask(now: observedAt) == nil)
}

@Test
func coachingTaskActionsApplyExactDurationsAndNeverReplay() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coaching-actions-\(UUID().uuidString)", isDirectory: true)
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

    func responses(_ action: PromptActionKind, taskID: String) throws -> (PromptResponseResult, PromptResponseResult) {
        let episode = try promptStore.enqueue(PromptDraft(
            decisionKey: "coaching:\(action.rawValue):\(taskID)",
            type: PromptNotificationCategory.gamingDrift.rawValue,
            title: "Choose the next step",
            summary: "Observed activity while work remains unfinished.",
            actions: [PromptAction(kind: action, title: action.rawValue)],
            payload: ["taskID": taskID]
        )).episode
        let token = PromptResponseToken.make(promptID: episode.id, action: action)
        return (
            try promptStore.respond(promptID: episode.id, action: action, actionToken: token, surface: .dashboard),
            try promptStore.respond(promptID: episode.id, action: action, actionToken: token, surface: .notification)
        )
    }

    var pair = try responses(.startRecommendedTask, taskID: "recommended")
    #expect(try router.apply(pair.0) == .coachingTaskStarted(taskID: "recommended"))
    #expect(try router.apply(pair.1) == .none)

    pair = try responses(.startShortSprint, taskID: "recovery")
    #expect(try router.apply(pair.0) == .coachingSprintStarted(taskID: "recovery", durationMinutes: 10))
    #expect(try router.apply(pair.1) == .none)
    #expect(try execution.snapshot(for: ["recovery"], now: now)["recovery"]?.sprint?.durationMinutes == 10)

    pair = try responses(.startWorkSprint, taskID: "work")
    #expect(try router.apply(pair.0) == .coachingSprintStarted(taskID: "work", durationMinutes: 20))
    #expect(try router.apply(pair.1) == .none)
    #expect(try execution.snapshot(for: ["work"], now: now)["work"]?.sprint?.durationMinutes == 20)

    try execution.apply(.pause, taskID: "work", at: now.addingTimeInterval(1))
    pair = try responses(.returnToActiveTask, taskID: "work")
    #expect(try router.apply(pair.0) == .coachingTaskStarted(taskID: "work"))
    #expect(try router.apply(pair.1) == .none)
    var workSnapshot = try execution.snapshot(for: ["work"], now: now)["work"]
    #expect(workSnapshot?.state == .active)
    #expect(workSnapshot?.sprint?.durationMinutes == 20)

    pair = try responses(.pauseTask, taskID: "stale-payload")
    #expect(try router.apply(pair.0) == .coachingTaskPaused(taskID: "work"))
    #expect(try router.apply(pair.1) == .none)
    workSnapshot = try execution.snapshot(for: ["work"], now: now)["work"]
    #expect(workSnapshot?.state == .paused)
    #expect(workSnapshot?.sprint?.durationMinutes == 20)
    #expect(workSnapshot?.sprint?.state == .paused)

    try execution.apply(.start, taskID: "end-day", at: now.addingTimeInterval(2))
    pair = try responses(.endWorkday, taskID: "different-stale-payload")
    #expect(try router.apply(pair.0) == .coachingWorkdayEnded(taskID: "end-day"))
    #expect(try router.apply(pair.1) == .none)
    let ended = try execution.snapshot(for: ["end-day"], now: now)["end-day"]
    #expect(ended?.state == .paused)
    #expect(ended?.latestPauseReason == .endingWorkday)
}
