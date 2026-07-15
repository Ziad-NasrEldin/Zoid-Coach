import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func zc061008FutureRuleClassifiesOnlyLaterMatchingObservationAndIsIdempotent() throws {
    let fixture = try ZC061008JourneyFixture()
    defer { fixture.remove() }
    try fixture.seedHistoricalCorrectionAndRule()
    try fixture.writeObservation(
        epoch: fixture.futureEpoch,
        application: "Safari",
        title: fixture.privateTitle,
        url: fixture.privateURL
    )

    let first = try fixture.archive.ingestToday(from: fixture.screenwatchRoot, now: fixture.now)
    let second = try fixture.archive.ingestToday(from: fixture.screenwatchRoot, now: fixture.now)
    #expect(first.insertedCount == 1)
    #expect(second.insertedCount == 0)
    #expect(try fixture.rawClassification(epoch: fixture.historicalEpoch) == .unknown)
    #expect(try fixture.rawClassification(epoch: fixture.futureEpoch) == .work)
    #expect(try fixture.correctionClassification() == .work)
    #expect(try fixture.activeRules() == 1)
    #expect(try fixture.behaviorCount(epoch: fixture.futureEpoch) == 1)
    #expect(try fixture.reopenedSessions().filter { $0.application == "Safari" }.count == 2)
    #expect(try fixture.reopenedSessions().allSatisfy { $0.classification == .work })
    #expect(try fixture.researchCount() == 0)
}

@Test(arguments: [
    ZC061008Boundary.preEffective,
    .nonmatching,
    .removedRule,
])
func zc061008RuleBoundariesDoNotOverreach(boundary: ZC061008Boundary) throws {
    let fixture = try ZC061008JourneyFixture()
    defer { fixture.remove() }
    try fixture.seedHistoricalCorrectionAndRule()
    let epoch: Int64
    let application: String
    switch boundary {
    case .preEffective:
        epoch = fixture.ruleEffectiveEpoch - 60
        application = "Safari"
    case .nonmatching:
        epoch = fixture.futureEpoch
        application = "Unmapped Browser"
    case .removedRule:
        epoch = fixture.futureEpoch
        application = "Safari"
        try fixture.removeRule()
    }
    try fixture.writeObservation(
        epoch: epoch,
        application: application,
        title: fixture.privateTitle,
        url: fixture.privateURL
    )

    #expect(try fixture.archive.ingestToday(from: fixture.screenwatchRoot, now: fixture.now).insertedCount == 1)
    #expect(try fixture.rawClassification(epoch: epoch) == .unknown)
    #expect(try fixture.rawClassification(epoch: fixture.historicalEpoch) == .unknown)
    #expect(try fixture.correctionClassification() == .work)
    #expect(try fixture.researchCount() == 0)
    if boundary == .removedRule {
        #expect(try fixture.activeRules() == 0)
    } else {
        #expect(try fixture.activeRules() == 1)
    }
}

@Test
func zc061008InvalidRuleSchemaFailsClosedWithoutIngestingObservation() throws {
    let fixture = try ZC061008JourneyFixture()
    defer { fixture.remove() }
    try fixture.seedHistoricalCorrectionAndRule()
    try fixture.writeObservation(
        epoch: fixture.futureEpoch,
        application: "Safari",
        title: fixture.privateTitle,
        url: fixture.privateURL
    )
    try fixture.replaceRuleTableWithInvalidSchema()

    #expect(throws: ScreenwatchArchiveError.self) {
        _ = try fixture.archive.ingestToday(from: fixture.screenwatchRoot, now: fixture.now)
    }
    #expect(try fixture.behaviorCount(epoch: fixture.futureEpoch) == 0)
    #expect(try fixture.rawClassification(epoch: fixture.historicalEpoch) == .unknown)
    #expect(try fixture.correctionClassification() == .work)
}

private enum ZC061008Boundary: CaseIterable, Sendable {
    case preEffective
    case nonmatching
    case removedRule
}

private final class ZC061008JourneyFixture {
    let root: URL
    let screenwatchRoot: URL
    let dayDirectory: URL
    let databaseURL: URL
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let sourceDay = "2026-07-14"
    let historicalEpoch: Int64 = 1_783_996_400
    let ruleEffectiveEpoch: Int64 = 1_783_998_200
    let futureEpoch: Int64 = 1_783_999_970
    let privateTitle = "qa-zc061008-private-future-window"
    let privateURL = "https://qa-zc061008.private.invalid/token"
    let archive: ScreenwatchArchive

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zc061008-journey-\(UUID().uuidString)", isDirectory: true)
        screenwatchRoot = root.appendingPathComponent("Screenwatch/days", isDirectory: true)
        dayDirectory = screenwatchRoot.appendingPathComponent(sourceDay, isDirectory: true)
        try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("zoid.sqlite")
        archive = try ScreenwatchArchive(databaseURL: databaseURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func seedHistoricalCorrectionAndRule() throws {
        try execute("""
        INSERT INTO behavior_records(
            source_day, epoch, time_label, app_name, window_title, url,
            has_screenshot, screenshot_path, ingested_at, classification,
            classification_policy_version
        ) VALUES (
            '\(sourceDay)', \(historicalEpoch), 'qa-zc061008-history', 'Safari',
            '', '', 0, NULL, '2026-07-14T02:33:20Z', 'unknown', 1
        );
        INSERT INTO daily_review_corrections(
            id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc
        ) VALUES (
            'qa-zc061008-correction', '\(sourceDay)', \(historicalEpoch),
            \(historicalEpoch + 60), 'work', NULL, '2026-07-14T02:34:20Z'
        );
        INSERT INTO app_classification_correction_rules(
            normalized_app, display_app, classification, state, source_day,
            source_session_start_epoch, effective_from_epoch, created_at_utc
        ) VALUES (
            'safari', 'Safari', 'work', 'active', '\(sourceDay)',
            \(historicalEpoch), \(ruleEffectiveEpoch), '2026-07-14T03:03:20Z'
        );
        """)
    }

    func removeRule() throws {
        try execute("""
        INSERT INTO app_classification_correction_rules(
            normalized_app, display_app, classification, state, source_day,
            source_session_start_epoch, effective_from_epoch, created_at_utc
        ) VALUES (
            'safari', 'Safari', NULL, 'removed', NULL,
            NULL, \(futureEpoch - 30), '2026-07-14T03:32:20Z'
        );
        """)
    }

    func writeObservation(epoch: Int64, application: String, title: String, url: String) throws {
        let encodedApplication = try JSONEncoder().encode(application)
        let encodedTitle = try JSONEncoder().encode(title)
        let encodedURL = try JSONEncoder().encode(url)
        let appJSON = String(decoding: encodedApplication, as: UTF8.self)
        let titleJSON = String(decoding: encodedTitle, as: UTF8.self)
        let urlJSON = String(decoding: encodedURL, as: UTF8.self)
        let line = "{\"t\":\"09-59-30\",\"epoch\":\(epoch),\"app\":\(appJSON),\"window\":\(titleJSON),\"url\":\(urlJSON),\"img\":false}\n"
        try Data(line.utf8).write(to: dayDirectory.appendingPathComponent("log.jsonl"))
    }

    func reopenedSessions() throws -> [DailyReviewSession] {
        try DailyReviewStore(databaseURL: databaseURL).load(sourceDay: sourceDay).sessions
    }

    func rawClassification(epoch: Int64) throws -> BehaviorClassification? {
        try scalarText("SELECT classification FROM behavior_records WHERE epoch = \(epoch);")
            .flatMap(BehaviorClassification.init(rawValue:))
    }

    func correctionClassification() throws -> BehaviorClassification? {
        try scalarText("SELECT classification FROM daily_review_corrections WHERE id = 'qa-zc061008-correction';")
            .flatMap(BehaviorClassification.init(rawValue:))
    }

    func activeRules() throws -> Int {
        try scalarInt("""
        SELECT COUNT(*) FROM app_classification_correction_rules rule
        WHERE rule.state = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM app_classification_correction_rules newer
              WHERE newer.normalized_app = rule.normalized_app
                AND (newer.effective_from_epoch > rule.effective_from_epoch
                  OR (newer.effective_from_epoch = rule.effective_from_epoch AND newer.id > rule.id))
          );
        """)
    }

    func behaviorCount(epoch: Int64) throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM behavior_records WHERE epoch = \(epoch);")
    }

    func researchCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM behavior_records WHERE lower(COALESCE(classification, '')) = 'research';")
    }

    func replaceRuleTableWithInvalidSchema() throws {
        try execute("DROP TABLE app_classification_correction_rules; CREATE TABLE app_classification_correction_rules(normalized_app TEXT);")
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw ZC061008JourneyFixtureError.database }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ZC061008JourneyFixtureError.database
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        Int(try scalarText(sql).flatMap(Int.init) ?? -1)
    }

    private func scalarText(_ sql: String) throws -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw ZC061008JourneyFixtureError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw ZC061008JourneyFixtureError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
}

private enum ZC061008JourneyFixtureError: Error {
    case database
}
