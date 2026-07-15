import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func sustainedAmbiguityQueuesOnePrivacySafeOptionalConfirmation() throws {
    let fixture = try AmbiguousActivityFixture()
    defer { fixture.remove() }
    try fixture.startTask()
    try fixture.insertUnknown(minutes: 10)

    guard case let .queued(episode, wasInserted) = try fixture.service.produce() else {
        Issue.record("Expected an ambiguity confirmation")
        return
    }

    #expect(wasInserted)
    #expect(episode.type == AmbiguousActivityPromptService.promptType)
    #expect(episode.title == "Did this support Ship proposal?")
    #expect(episode.summary.contains("about 10 minutes in Safari"))
    #expect(episode.summary.contains("cannot show your intent"))
    #expect(episode.actions.map(\.kind) == [
        .classifyAsSupportingWork,
        .classifyAsGaming,
        .keepActivityUnknown
    ])
    #expect(episode.actions.first?.role == .primary)
    #expect(episode.allowsDismissal)
    #expect(!episode.summary.contains(fixture.privateTitle))
    #expect(!episode.summary.contains(fixture.privateURL))
    #expect(!episode.payload.values.contains(fixture.privateTitle))
    #expect(!episode.payload.values.contains(fixture.privateURL))
    #expect(try fixture.promptStore.unresolved().map(\.id) == [episode.id])
}

@Test
func supportingWorkResponseCorrectsTheExactSessionAndAttachesTheActiveTaskOnce() throws {
    let fixture = try AmbiguousActivityFixture()
    defer { fixture.remove() }
    try fixture.startTask()
    try fixture.insertUnknown(minutes: 10)
    let episode = try fixture.queuedEpisode()
    let token = PromptResponseToken.make(promptID: episode.id, action: .classifyAsSupportingWork)
    let first = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .classifyAsSupportingWork,
        actionToken: token,
        surface: .dashboard
    )
    let replay = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .classifyAsSupportingWork,
        actionToken: token,
        surface: .notification
    )
    let router = try fixture.router()

    #expect(try router.apply(first) == .ambiguousActivityClassified(
        promptID: episode.id,
        classification: .work,
        taskID: fixture.taskID
    ))
    #expect(try router.apply(replay) == .none)

    let fixtureNow = fixture.now
    let snapshot = try DailyReviewStore(
        databaseURL: fixture.databaseURL,
        now: { fixtureNow }
    ).load(sourceDay: fixture.sourceDay)
    #expect(snapshot.sessions.count == 1)
    #expect(snapshot.sessions.first?.classification == .work)
    #expect(snapshot.sessions.first?.taskID == fixture.taskID)
    #expect(snapshot.sessions.first?.observationCount == 10)
    #expect(try fixture.correctionCount() == 1)
    #expect(try fixture.service.produce() == .suppressed(.noCurrentAmbiguity))
}

@Test
func gamingResponseCorrectsWithoutAttachingTheActiveTask() throws {
    let gaming = try AmbiguousActivityFixture()
    defer { gaming.remove() }
    try gaming.startTask()
    try gaming.insertUnknown(minutes: 10)
    let gamingEpisode = try gaming.queuedEpisode()
    let gamingResult = try gaming.promptStore.respond(
        promptID: gamingEpisode.id,
        action: .classifyAsGaming,
        actionToken: PromptResponseToken.make(promptID: gamingEpisode.id, action: .classifyAsGaming),
        surface: .dashboard
    )
    #expect(try gaming.router().apply(gamingResult) == .ambiguousActivityClassified(
        promptID: gamingEpisode.id,
        classification: .gaming,
        taskID: nil
    ))
    let gamingNow = gaming.now
    let gamingSnapshot = try DailyReviewStore(
        databaseURL: gaming.databaseURL,
        now: { gamingNow }
    ).load(sourceDay: gaming.sourceDay)
    #expect(gamingSnapshot.sessions.first?.classification == .gaming)
    #expect(gamingSnapshot.sessions.first?.taskID == nil)
}

@Test
func keepUnknownChangesNothingAndNeverRepromptsTheSameSession() throws {
    let unknown = try AmbiguousActivityFixture()
    defer { unknown.remove() }
    try unknown.startTask()
    try unknown.insertUnknown(minutes: 10)
    let unknownEpisode = try unknown.queuedEpisode()
    let unknownResult = try unknown.promptStore.respond(
        promptID: unknownEpisode.id,
        action: .keepActivityUnknown,
        actionToken: PromptResponseToken.make(promptID: unknownEpisode.id, action: .keepActivityUnknown),
        surface: .dashboard
    )
    let unknownRouter = try unknown.router()
    let unknownEffect = try unknownRouter.apply(unknownResult)
    #expect(unknownEffect == .ambiguousActivityKeptUnknown(
        promptID: unknownEpisode.id
    ))
    let unknownCorrectionCount = try unknown.correctionCount()
    #expect(unknownCorrectionCount == 0)
    let reopenedNow = unknown.now
    let reopenedPromptStore = try PromptInboxStore(
        databaseURL: unknown.databaseURL,
        now: { reopenedNow }
    )
    let reopenedService = try AmbiguousActivityPromptService(
        databaseURL: unknown.databaseURL,
        promptStore: reopenedPromptStore,
        now: { reopenedNow }
    )
    let repeatedResult = try reopenedService.produce()
    #expect(repeatedResult == .suppressed(.alreadyHandled))
    let unresolved = try unknown.promptStore.unresolved()
    #expect(unresolved.isEmpty)
}

@Test
func ambiguityConfirmationRequiresFreshTenMinuteOverlapWithAnActiveTask() throws {
    let noTask = try AmbiguousActivityFixture()
    defer { noTask.remove() }
    try noTask.insertUnknown(minutes: 10)
    #expect(try noTask.service.produce() == .suppressed(.noActiveTask))

    let short = try AmbiguousActivityFixture()
    defer { short.remove() }
    try short.startTask()
    try short.insertUnknown(minutes: 9)
    #expect(try short.service.produce() == .suppressed(.belowMaterialThreshold))

    let lateTask = try AmbiguousActivityFixture()
    defer { lateTask.remove() }
    try lateTask.insertUnknown(minutes: 10)
    try lateTask.startTask(at: lateTask.now.addingTimeInterval(-5 * 60))
    #expect(try lateTask.service.produce() == .suppressed(.belowMaterialThreshold))

    let stale = try AmbiguousActivityFixture()
    defer { stale.remove() }
    try stale.startTask()
    try stale.insertUnknown(minutes: 10, endingAt: stale.now.addingTimeInterval(-4 * 60))
    #expect(try stale.service.produce() == .suppressed(.staleEvidence))

    let certain = try AmbiguousActivityFixture()
    defer { certain.remove() }
    try certain.startTask()
    try certain.insertUnknown(minutes: 10, classification: .work)
    #expect(try certain.service.produce() == .suppressed(.noCurrentAmbiguity))
}

private final class AmbiguousActivityFixture {
    let root: URL
    let databaseURL: URL
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let sourceDay = "2026-07-13"
    let taskID = "task-1"
    let privateTitle = "Secret acquisition notes"
    let privateURL = "https://private.example/acquisition"
    let promptStore: PromptInboxStore
    let service: AmbiguousActivityPromptService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-ambiguity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("zoid.sqlite")
        let fixedNow = now
        promptStore = try PromptInboxStore(
            databaseURL: databaseURL,
            now: { fixedNow },
            makeID: { "ambiguity-prompt" }
        )
        service = try AmbiguousActivityPromptService(
            databaseURL: databaseURL,
            promptStore: promptStore,
            now: { fixedNow }
        )
        try execute("INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES ('task-1', 'Ship proposal', 9, 0, '2026-07-13T09:00:00Z', 'local');")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func startTask(at date: Date? = nil) throws {
        try TaskExecutionStore(databaseURL: databaseURL).apply(
            .start,
            taskID: taskID,
            at: date ?? now.addingTimeInterval(-11 * 60)
        )
    }

    func insertUnknown(
        minutes: Int,
        endingAt: Date? = nil,
        classification: BehaviorClassification = .unknown
    ) throws {
        let latest = Int64((endingAt ?? now.addingTimeInterval(-30)).timeIntervalSince1970)
        let first = latest - Int64(max(0, minutes - 1) * 60)
        for offset in 0 ..< minutes {
            let epoch = first + Int64(offset * 60)
            try execute("""
            INSERT INTO behavior_records(
                source_day, epoch, time_label, app_name, window_title, url,
                has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
            ) VALUES (
                '\(sourceDay)', \(epoch), '09-00-00', 'Safari', '\(privateTitle)', '\(privateURL)',
                0, NULL, '2026-07-13T10:00:00Z', '\(classification.rawValue)', 1
            );
            """)
        }
    }

    func queuedEpisode() throws -> PromptEpisode {
        guard case let .queued(episode, true) = try service.produce() else {
            throw AmbiguousActivityFixtureError.expectedPrompt
        }
        return episode
    }

    func router() throws -> PromptResponseEffectRouter {
        PromptResponseEffectRouter(
            outbox: try ActionOutboxStore(databaseURL: databaseURL),
            meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
            promptStore: promptStore,
            ambiguousActivityPrompts: service
        )
    }

    func correctionCount() throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw AmbiguousActivityFixtureError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM daily_review_corrections;", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw AmbiguousActivityFixtureError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AmbiguousActivityFixtureError.database }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw AmbiguousActivityFixtureError.database }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw AmbiguousActivityFixtureError.database
        }
    }
}

private enum AmbiguousActivityFixtureError: Error {
    case expectedPrompt
    case database
}
