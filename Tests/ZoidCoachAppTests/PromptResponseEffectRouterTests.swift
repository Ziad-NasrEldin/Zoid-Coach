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
    let second = try promptStore.respond(promptID: episode.id, action: .addMeeting, actionToken: token, surface: .atoll)
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let router = PromptResponseEffectRouter(outbox: outbox, meetingArchive: archive)

    let firstEffect = try router.apply(first)
    let secondEffect = try router.apply(second)

    #expect(firstEffect != .none)
    #expect(secondEffect == .none)
    #expect(try outbox.recentCommands().filter { $0.type == .createConfirmedMeeting }.count == 1)
    #expect(try archive.meetingCandidate(id: candidate.id)?.state == "accepted")
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
    _ = try archive.ingestToday(from: root, now: Date(timeIntervalSince1970: 1_783_663_200))
    let ocr = ScreenshotOCRResult(blocks: [
        OCRTextBlock(text: "Meeting tomorrow at 3 pm", confidence: 0.95, boundingBox: NormalizedBoundingBox(x: 0, y: 0, width: 1, height: 1), localeHint: "en")
    ])
    _ = try await archive.analyzePendingWhatsAppScreenshots(
        using: PromptEffectRecognizer(result: ocr),
        cipher: try LocalEvidenceCipher(keyData: Data(repeating: 4, count: 32))
    )
    let candidate = try #require(archive.unresolvedMeetingCandidates().first)
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
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
