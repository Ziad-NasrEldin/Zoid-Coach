import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func screenwatchSetupFindsAHealthyDefaultStreamWithoutExposingContent() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "default-healthy")
    defer { fixture.remove() }
    let secret = "PRIVATE CLIENT WINDOW"
    try fixture.writeValidRecord(in: fixture.runtime.screenwatchDirectory, secret: secret)
    let service = fixture.makeService()

    let status = await service.inspect(now: fixture.now)

    #expect(status.health == .healthy)
    #expect(status.continuation == .ready)
    #expect(status.source == .defaultLocation)
    #expect(status.repair == .none)
    #expect(status.validRecordCount == 1)
    #expect(!fixture.visibleText(status).contains(secret))
    #expect(!fixture.visibleText(status).contains(fixture.root.path))
}

@Test
func screenwatchSetupReportsAMissingDefaultAsExplicitDegradedMode() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "default-missing")
    defer { fixture.remove() }
    let service = fixture.makeService()

    let status = await service.inspect(now: fixture.now)

    #expect(status.health == .missing)
    #expect(status.continuation == .degraded)
    #expect(status.repair == .chooseFolder)
    #expect(status.validRecordCount == 0)
}

@Test
func screenwatchSetupDefaultsToThirtySecondsAndAllowsAConfiguredStaleThreshold() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "stale-threshold")
    defer { fixture.remove() }
    try fixture.writeValidRecord(
        in: fixture.runtime.screenwatchDirectory,
        secret: "Stale private window",
        epoch: Int(fixture.now.timeIntervalSince1970) - 31
    )
    let defaultService = fixture.makeService()
    let relaxedService = fixture.makeService(staleThreshold: 60)

    let defaultStatus = await defaultService.inspect(now: fixture.now)
    let relaxedStatus = await relaxedService.inspect(now: fixture.now)

    #expect(defaultStatus.health == .stale)
    #expect(defaultStatus.continuation == .degraded)
    #expect(defaultStatus.repair == .recheck)
    #expect(relaxedStatus.health == .healthy)
}

@Test
func screenwatchSetupRejectsMalformedSchemaWithPrivacySafeDiagnostics() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "default-malformed")
    defer { fixture.remove() }
    let secretTitle = "SECRET MERGER TITLE"
    let secretURL = "https://private.example/client"
    try fixture.writeRawLine(
        #"{"t":"now","epoch":"wrong","app":"SecretApp","window":"\#(secretTitle)","url":"\#(secretURL)","img":true}"#,
        in: fixture.runtime.screenwatchDirectory
    )
    let service = fixture.makeService()

    let status = await service.inspect(now: fixture.now)
    let visibleText = fixture.visibleText(status)

    #expect(status.health == .malformed)
    #expect(status.continuation == .degraded)
    #expect(status.repair == .recheck)
    #expect(!visibleText.contains(secretTitle))
    #expect(!visibleText.contains(secretURL))
    #expect(!visibleText.contains("SecretApp"))
    #expect(!visibleText.contains(fixture.runtime.screenwatchDirectory.path))
}

@Test
func screenwatchSetupUsesAndPersistsAnAlternateDaysFolder() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "alternate")
    defer { fixture.remove() }
    let alternate = fixture.root.appendingPathComponent("Chosen Days", isDirectory: true)
    try fixture.writeValidRecord(in: alternate, secret: "Alternate private window")
    let codec = TestScreenwatchBookmarkCodec()
    let service = fixture.makeService(bookmarkAccess: codec.access)

    let selected = try await service.selectAlternateDaysDirectory(alternate, now: fixture.now)

    #expect(selected.health == .healthy)
    #expect(selected.source == .alternateFolder)
    #expect(FileManager.default.fileExists(atPath: fixture.bookmarkFileURL.path))
    #expect(codec.createCount == 1)
    #expect(codec.startCount == 1)
    #expect(codec.stopCount == 1)
}

@Test
func screenwatchSetupRejectsAStaleBookmarkWithoutFallingBack() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "stale-bookmark")
    defer { fixture.remove() }
    let alternate = fixture.root.appendingPathComponent("Chosen Days", isDirectory: true)
    try fixture.writeValidRecord(in: alternate, secret: "Stale bookmark record")
    let codec = TestScreenwatchBookmarkCodec()
    let service = fixture.makeService(bookmarkAccess: codec.access)
    _ = try await service.selectAlternateDaysDirectory(alternate, now: fixture.now)
    codec.isStale = true

    let refreshed = await service.recheck(now: fixture.now)

    #expect(refreshed.health == .bookmarkUnavailable)
    #expect(refreshed.source == .alternateFolder)
    #expect(codec.createCount == 1)
    #expect(codec.resolveCount == 2)
}

@Test
func screenwatchSetupExposesRepairWhenBookmarkResolutionFails() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "broken-bookmark")
    defer { fixture.remove() }
    fixture.defaults.set(Data("not-a-bookmark".utf8), forKey: ScreenwatchSetupService.bookmarkDefaultsKey)
    let codec = TestScreenwatchBookmarkCodec()
    codec.rejectResolution = true
    let service = fixture.makeService(bookmarkAccess: codec.access)

    let status = await service.inspect(now: fixture.now)

    #expect(status.health == .bookmarkUnavailable)
    #expect(status.continuation == .unavailable)
    #expect(status.repair == .reauthorizeFolder)
}

@Test
func screenwatchAlternateFolderSurvivesAServiceRestart() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "restart")
    defer { fixture.remove() }
    let alternate = fixture.root.appendingPathComponent("Chosen Days", isDirectory: true)
    try fixture.writeValidRecord(in: alternate, secret: "Restart record")
    let codec = TestScreenwatchBookmarkCodec()
    let first = fixture.makeService(bookmarkAccess: codec.access)
    _ = try await first.selectAlternateDaysDirectory(alternate, now: fixture.now)

    let restarted = fixture.makeService(bookmarkAccess: codec.access)
    let status = await restarted.inspect(now: fixture.now)

    #expect(status.health == .healthy)
    #expect(status.source == .alternateFolder)
    #expect(codec.resolveCount == 2)
}

@Test
func screenwatchSetupKeepsQABookmarksInsideEachRunAndOutOfProductionDefaults() async throws {
    let first = try ScreenwatchSetupFixture(name: "qa-first", mode: .qa)
    let second = try ScreenwatchSetupFixture(name: "qa-second", mode: .qa)
    defer {
        first.remove()
        second.remove()
    }
    let productionValueBefore = UserDefaults.standard.data(
        forKey: ScreenwatchSetupService.bookmarkDefaultsKey
    )
    let alternate = first.root.appendingPathComponent("Chosen Days", isDirectory: true)
    try first.writeValidRecord(in: alternate, secret: "QA private record")
    let codec = TestScreenwatchBookmarkCodec()
    let firstService = first.makeService(bookmarkAccess: codec.access)
    _ = try await firstService.selectAlternateDaysDirectory(alternate, now: first.now)

    let secondStatus = await second.makeService(bookmarkAccess: codec.access).inspect(now: second.now)
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("outside-qa-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    #expect(secondStatus.source == .defaultLocation)
    #expect(secondStatus.health == .missing)
    await #expect(throws: ScreenwatchSetupServiceError.selectedFolderOutsideQARunRoot) {
        try await firstService.selectAlternateDaysDirectory(outside, now: first.now)
    }
    #expect(
        UserDefaults.standard.data(forKey: ScreenwatchSetupService.bookmarkDefaultsKey)
            == productionValueBefore
    )
}

@Test
func screenwatchSetupRejectsASymlinkedAlternateFolder() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "symlink")
    defer { fixture.remove() }
    let target = fixture.root.appendingPathComponent("Real Days", isDirectory: true)
    let link = fixture.root.appendingPathComponent("Linked Days", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let service = fixture.makeService(bookmarkAccess: TestScreenwatchBookmarkCodec().access)

    await #expect(throws: ScreenwatchSetupServiceError.unsafePath) {
        try await service.selectAlternateDaysDirectory(link, now: fixture.now)
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.bookmarkFileURL.path))
}

@Test
func screenwatchSetupRejectsASymlinkedDayDirectoryBelowAnAlternateFolder() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "nested-day-symlink")
    defer { fixture.remove() }
    let alternate = fixture.root.appendingPathComponent("Chosen Days", isDirectory: true)
    let target = fixture.root.appendingPathComponent("Real Days", isDirectory: true)
    try fixture.writeValidRecord(in: target, secret: "Private target")
    try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
    let dayLink = alternate.appendingPathComponent("2027-01-15", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        at: dayLink,
        withDestinationURL: target.appendingPathComponent("2027-01-15", isDirectory: true)
    )
    let service = fixture.makeService(bookmarkAccess: TestScreenwatchBookmarkCodec().access)

    let status = try await service.selectAlternateDaysDirectory(alternate, now: fixture.now)

    #expect(status.health == .unsafePath)
    #expect(status.continuation == .unavailable)
    #expect(status.repair == .reauthorizeFolder)
}

@Test
func screenwatchSetupRejectsASymlinkedLogBelowAnAlternateFolder() async throws {
    let fixture = try ScreenwatchSetupFixture(name: "nested-log-symlink")
    defer { fixture.remove() }
    let alternate = fixture.root.appendingPathComponent("Chosen Days", isDirectory: true)
    let target = fixture.root.appendingPathComponent("Real Log", isDirectory: true)
    try fixture.writeValidRecord(in: target, secret: "Private target")
    let alternateDay = alternate.appendingPathComponent("2027-01-15", isDirectory: true)
    try FileManager.default.createDirectory(at: alternateDay, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: alternateDay.appendingPathComponent("log.jsonl"),
        withDestinationURL: target
            .appendingPathComponent("2027-01-15", isDirectory: true)
            .appendingPathComponent("log.jsonl")
    )
    let service = fixture.makeService(bookmarkAccess: TestScreenwatchBookmarkCodec().access)

    let status = try await service.selectAlternateDaysDirectory(alternate, now: fixture.now)

    #expect(status.health == .unsafePath)
    #expect(status.continuation == .unavailable)
    #expect(status.repair == .reauthorizeFolder)
}

private final class TestScreenwatchBookmarkCodec: @unchecked Sendable {
    private let lock = NSLock()
    private var creates = 0
    private var resolves = 0
    private var starts = 0
    private var stops = 0
    private var stale = false
    private var rejects = false

    var isStale: Bool {
        get { lock.withLock { stale } }
        set { lock.withLock { stale = newValue } }
    }

    var rejectResolution: Bool {
        get { lock.withLock { rejects } }
        set { lock.withLock { rejects = newValue } }
    }

    var createCount: Int { lock.withLock { creates } }
    var resolveCount: Int { lock.withLock { resolves } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    var access: ScreenwatchBookmarkAccess {
        ScreenwatchBookmarkAccess(
            create: { [self] url in
                lock.withLock { creates += 1 }
                return Data(url.path.utf8)
            },
            resolve: { [self] data in
                let values = lock.withLock { () -> (Bool, Bool) in
                    resolves += 1
                    return (stale, rejects)
                }
                if values.1 { throw TestBookmarkError.rejected }
                return ScreenwatchBookmarkResolution(
                    url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true),
                    isStale: values.0
                )
            },
            startAccess: { [self] _ in
                lock.withLock { starts += 1 }
                return true
            },
            stopAccess: { [self] _ in
                lock.withLock { stops += 1 }
            }
        )
    }
}

private enum TestBookmarkError: Error {
    case rejected
}

private struct ScreenwatchSetupFixture {
    enum Mode {
        case production
        case qa
    }

    let root: URL
    let runtime: RuntimeEnvironment
    let defaults: UserDefaults
    let suiteName: String
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar: Calendar
    var bookmarkFileURL: URL {
        runtime.applicationSupportRoot
            .appendingPathComponent("Zoid Coach", isDirectory: true)
            .appendingPathComponent("screenwatch-source-v1.bookmark", isDirectory: false)
    }

    init(name: String, mode: Mode = .production) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-screenwatch-setup-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        switch mode {
        case .production:
            runtime = RuntimeEnvironment.production(directories: .init(
                home: root.appendingPathComponent("Home", isDirectory: true),
                applicationSupport: root.appendingPathComponent("Application Support", isDirectory: true)
            ))
            suiteName = "com.ziadnasreldin.ZoidCoach.screenwatch-tests.\(UUID().uuidString)"
        case .qa:
            runtime = try RuntimeEnvironment.resolve(
                arguments: ["--qa-run-root", root.path],
                processEnvironment: [:]
            ).environment
            suiteName = try #require(runtime.userDefaultsSuiteName)
        }
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = fixedCalendar
    }

    func makeService(
        bookmarkAccess: ScreenwatchBookmarkAccess = TestScreenwatchBookmarkCodec().access,
        staleThreshold: TimeInterval = 30
    ) -> ScreenwatchSetupService {
        let repository = ScreenwatchSourceRepository(
            runtimeEnvironment: runtime,
            bookmarkFileURL: bookmarkFileURL,
            bookmarkAccess: bookmarkAccess,
            legacyDefaults: [defaults]
        )
        return ScreenwatchSetupService(
            repository: repository,
            calendar: calendar,
            staleThreshold: staleThreshold
        )
    }

    func writeValidRecord(
        in daysDirectory: URL,
        secret: String,
        epoch: Int? = nil
    ) throws {
        let record: [String: Any] = [
            "t": "2027-01-15T08:00:00Z",
            "epoch": epoch ?? Int(now.timeIntervalSince1970),
            "app": "PrivateApp",
            "window": secret,
            "url": "https://private.example/secret",
            "img": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: record)
        try writeRawLine(String(decoding: data, as: UTF8.self), in: daysDirectory)
    }

    func writeRawLine(_ line: String, in daysDirectory: URL) throws {
        let day = daysDirectory.appendingPathComponent("2027-01-15", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try Data((line + "\n").utf8).write(to: day.appendingPathComponent("log.jsonl"))
    }

    func visibleText(_ status: ScreenwatchSetupStatus) -> String {
        status.summary + " " + status.evidence
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
