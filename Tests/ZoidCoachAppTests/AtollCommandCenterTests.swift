import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func atollCommandCenterExposesTheDailyControlSurface() {
    let html = AtollCommandCenterDocumentBuilder().html(
        loopbackPort: 4312,
        presentationCapability: "test-capability"
    )

    #expect(html.contains("TODAY"))
    #expect(html.contains("DECISIONS"))
    #expect(html.contains("SYSTEM"))
    #expect(html.contains("Draft plan"))
    #expect(html.contains("Reserve plan"))
    #expect(html.contains("http://127.0.0.1:4312/v1/command-center"))
    #expect(html.contains("'/state'"))
    #expect(html.contains("'/tasks/'"))
    #expect(html.contains("'/prompts/'"))
    #expect(html.contains("'/automation/'"))
    #expect(html.contains("test-capability"))
    #expect(html.contains("height:100%"))
    #expect(html.contains("overflow-y:auto"))
    #expect(html.contains("font-size:19px"))
    #expect(html.utf8.count < 20_000)
}

@Test
func atollCommandCenterRoutesTaskCommandsThroughTheAgent() async throws {
    let capture = AtollCommandCapture()
    let snapshot = commandCenterSnapshot(taskState: .ready)
    let controller = AtollCommandCenterController(dependencies: .init(
        snapshot: { snapshot },
        prompts: { [] },
        policy: { UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo") },
        applyTask: { command, taskID in
            capture.record(command: command, taskID: taskID)
            return commandCenterSnapshot(taskState: .active)
        },
        respondToPrompt: { _, _ in },
        applyMutation: { _ in AgentMutationReceipt(accepted: true, message: "Accepted") }
    ))

    let response = await controller.handle(
        method: "POST",
        path: ["v1", "command-center", "tasks", "task-1", "start"],
        query: [:]
    )

    #expect(response.status == 200)
    #expect(capture.value?.0 == .start)
    #expect(capture.value?.1 == "task-1")
    #expect(String(decoding: response.body, as: UTF8.self).contains(#""state":"active""#))
}

@Test
func atollCommandCenterKeepsAppleDataReadOnlyInObserveMode() async throws {
    let capture = AtollObserveMutationCapture()
    let snapshot = commandCenterSnapshot(taskState: .active)
    let base = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let observePolicy = UserPolicy(
        schemaVersion: base.schemaVersion,
        operatingMode: .observe,
        automationPause: base.automationPause,
        schedule: base.schedule,
        calendar: base.calendar,
        privacy: base.privacy,
        wake: base.wake
    )
    let controller = AtollCommandCenterController(dependencies: .init(
        snapshot: { snapshot }, prompts: { [] }, policy: { observePolicy },
        applyTask: { _, _ in capture.record(); return snapshot },
        respondToPrompt: { _, _ in capture.record() },
        applyMutation: { _ in capture.record(); return AgentMutationReceipt(accepted: true, message: "Accepted") }
    ))

    let complete = await controller.handle(method: "POST", path: ["v1", "command-center", "tasks", "task-1", "complete"], query: [:])
    let reserve = await controller.handle(method: "POST", path: ["v1", "command-center", "actions", "schedule-plan"], query: [:])
    let meeting = await controller.handle(
        method: "POST",
        path: ["v1", "command-center", "meetings", "candidate-1", "save"],
        query: ["title": "Review", "start": "2026-07-10T18:00:00Z", "duration": "30", "destination": "calendar"]
    )

    #expect(complete.status == 409)
    #expect(reserve.status == 409)
    #expect(meeting.status == 409)
    #expect(capture.count == 0)
}

@Test
func atollCommandCenterRequiresItsPresentationCapability() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-command-center-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let promptStore = try PromptInboxStore(databaseURL: databaseURL)
    let promptHandler = AtollPromptActionHandler(
        promptStore: promptStore,
        effectRouter: PromptResponseEffectRouter(
            outbox: try ActionOutboxStore(databaseURL: databaseURL),
            meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL)
        )
    )
    let snapshot = commandCenterSnapshot(taskState: .ready)
    let controller = AtollCommandCenterController(dependencies: .init(
        snapshot: { snapshot }, prompts: { [] }, policy: { UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo") },
        applyTask: { _, _ in snapshot }, respondToPrompt: { _, _ in },
        applyMutation: { _ in AgentMutationReceipt(accepted: true, message: "Accepted") }
    ))
    let server = AtollPromptLoopbackServer(handler: promptHandler, commandCenterController: controller)
    let port = try await server.start()
    server.authorizeCommandCenter(presentationCapability: "right-capability")

    let unauthorized = try await commandCenterGET(port: port, capability: "wrong-capability")
    let authorized = try await commandCenterGET(port: port, capability: "right-capability")
    let duplicate = try await commandCenterGET(
        port: port,
        rawQuery: "capability=right-capability&capability=right-capability"
    )
    let foreignOrigin = try await commandCenterGET(
        port: port,
        rawQuery: "capability=right-capability",
        origin: "https://example.com"
    )
    let stillAuthorized = try await commandCenterGET(port: port, capability: "right-capability")

    #expect(unauthorized.0 == 404)
    #expect(authorized.0 == 200)
    #expect(authorized.1.contains("Ship Atoll controls"))
    #expect(duplicate.0 == 404)
    #expect(foreignOrigin.0 == 404)
    #expect(stillAuthorized.0 == 200)
    server.stop()
}

private final class AtollCommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (TaskActivityCommand, String)?
    var value: (TaskActivityCommand, String)? { lock.withLock { stored } }
    func record(command: TaskActivityCommand, taskID: String) { lock.withLock { stored = (command, taskID) } }
}

private final class AtollObserveMutationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0
    var count: Int { lock.withLock { storedCount } }
    func record() { lock.withLock { storedCount += 1 } }
}

private func commandCenterSnapshot(taskState: TaskExecutionState) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_783_667_600),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: "Ship Atoll controls",
        taskRows: [TodayTaskRow(taskID: "task-1", title: "Ship Atoll controls", estimateMinutes: 45, dueDate: nil, urgency: .high, state: taskState, isMainObjective: true)],
        activeTask: taskState == .active ? ActiveTaskSnapshot(taskID: "task-1", startedAt: Date(timeIntervalSince1970: 1_783_667_600), elapsedMinutes: 0) : nil,
        recommendation: NextTaskRecommendation(taskID: "task-1", sentence: "Start now.", reasons: [.mainObjective]),
        behavior: BehaviorSummary(workMinutes: 30),
        coverage: TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date(timeIntervalSince1970: 1_783_667_600)),
        gaming: GamingStatus(budgetMinutes: 60, usedMinutes: 0, unlockedRemainingMinutes: 60, nextUnlockReason: "Complete priority work.", confidenceIsLimited: false),
        sourceFreshnessExplanation: "All current"
    )
}

private func commandCenterGET(port: UInt16, capability: String) async throws -> (Int, String) {
    try await commandCenterGET(port: port, rawQuery: "capability=\(capability)")
}

private func commandCenterGET(port: UInt16, rawQuery: String, origin: String? = nil) async throws -> (Int, String) {
    let url = URL(string: "http://127.0.0.1:\(port)/v1/command-center/state?\(rawQuery)")!
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
    let (data, response) = try await URLSession.shared.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
}
