import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func canonicalScreenwatchBookmarkMigratesOnceWithPrivateAtomicStorage() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "legacy-migration")
    defer { fixture.remove() }
    let alternate = try fixture.makeDaysDirectory(named: "Alternate")
    fixture.defaults.set(Data(alternate.path.utf8), forKey: ScreenwatchSourceRepository.legacyBookmarkDefaultsKey)
    let repository = fixture.repository()

    let lease = try repository.resolveCanonicalSource()

    #expect(lease.rootURL.standardizedFileURL == alternate.standardizedFileURL)
    #expect(lease.source == .alternateBookmark)
    #expect(fixture.defaults.data(forKey: ScreenwatchSourceRepository.legacyBookmarkDefaultsKey) == nil)
    #expect(FileManager.default.fileExists(atPath: fixture.bookmarkFileURL.path))
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.bookmarkFileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func canonicalScreenwatchLeaseRetainsSecurityScopeUntilRelease() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "scope-lifetime")
    defer { fixture.remove() }
    let alternate = try fixture.makeDaysDirectory(named: "Alternate")
    let counter = ScopeCounter()
    let repository = fixture.repository(counter: counter)
    try repository.saveAlternate(alternate)
    var lease: ScreenwatchDirectoryLease? = try repository.resolveCanonicalSource()

    #expect(counter.starts == 1)
    #expect(counter.stops == 0)
    #expect(lease?.rootURL.standardizedFileURL == alternate.standardizedFileURL)

    lease = nil
    #expect(counter.stops == 1)
}

@Test
func canonicalScreenwatchStaleOrInvalidBookmarkNeverFallsBackToDefault() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "no-fallback")
    defer { fixture.remove() }
    let alternate = try fixture.makeDaysDirectory(named: "Alternate")
    let stale = fixture.repository(isStale: true)
    try stale.saveAlternate(alternate)

    #expect(throws: ScreenwatchSourceResolutionError.staleBookmark) {
        _ = try stale.resolveCanonicalSource()
    }

    try Data("not-a-bookmark".utf8).write(to: fixture.bookmarkFileURL, options: .atomic)
    let invalid = fixture.repository(rejectResolution: true)
    #expect(throws: ScreenwatchSourceResolutionError.invalidBookmark) {
        _ = try invalid.resolveCanonicalSource()
    }
}

@Test
func canonicalScreenwatchQABookmarkCannotEscapeOrCrossRunRoots() throws {
    let first = try CanonicalScreenwatchFixture(name: "qa-a")
    let second = try CanonicalScreenwatchFixture(name: "qa-b")
    defer {
        first.remove()
        second.remove()
    }
    let firstAlternate = try first.makeDaysDirectory(named: "Alternate")
    let firstRepository = first.repository()
    try firstRepository.saveAlternate(firstAlternate)
    try FileManager.default.createDirectory(
        at: second.bookmarkFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: first.bookmarkFileURL, to: second.bookmarkFileURL)

    #expect(throws: ScreenwatchSourceResolutionError.outsideQARunRoot) {
        _ = try second.repository().resolveCanonicalSource()
    }
}

@Test
func canonicalScreenwatchBookmarkReadsRemainWholeDuringConcurrentReplacement() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "atomic-concurrency")
    defer { fixture.remove() }
    let first = try fixture.makeDaysDirectory(named: "First")
    let second = try fixture.makeDaysDirectory(named: "Second")
    let writerA = fixture.repository()
    let writerB = fixture.repository()
    let reader = fixture.repository()
    try writerA.saveAlternate(first)
    let failures = FailureRecorder()

    DispatchQueue.concurrentPerform(iterations: 120) { index in
        do {
            switch index % 3 {
            case 0: try writerA.saveAlternate(first)
            case 1: try writerB.saveAlternate(second)
            default:
                let lease = try reader.resolveCanonicalSource()
                let path = lease.rootURL.standardizedFileURL
                guard path == first.standardizedFileURL || path == second.standardizedFileURL else {
                    throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
                }
            }
        } catch {
            failures.record(error)
        }
    }

    #expect(failures.errors.isEmpty)
}

@Test
func canonicalScreenwatchDescriptorRejectsLogSwappedToSymlink() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "symlink-swap")
    defer { fixture.remove() }
    let source = try fixture.makeDaysDirectory(named: "Source")
    let day = source.appendingPathComponent("2026-07-12", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let log = day.appendingPathComponent("log.jsonl")
    try Data("safe\n".utf8).write(to: log)
    let outside = fixture.root.appendingPathComponent("outside.jsonl")
    try Data("private\n".utf8).write(to: outside)
    let lease = try ScreenwatchDirectoryLease(rootURL: source, source: .defaultLocation)
    try FileManager.default.removeItem(at: log)
    try FileManager.default.createSymbolicLink(at: log, withDestinationURL: outside)

    #expect(throws: (any Error).self) {
        _ = try lease.data(at: ["2026-07-12", "log.jsonl"])
    }
}

@Test @MainActor
func appModelConsumesCanonicalAlternateScreenwatchAfterFreshResolution() async throws {
    let fixture = try CanonicalScreenwatchFixture(name: "app-consumer")
    defer { fixture.remove() }
    let alternate = try fixture.makeDaysDirectory(named: "Alternate")
    try fixture.writeCurrentLog(in: alternate)
    let repository = fixture.repository()
    try repository.saveAlternate(alternate)
    let model = AppModel(
        runtimeEnvironment: fixture.runtime,
        screenwatchSourceRepository: repository
    )

    model.checkSource(.screenwatch)
    for _ in 0..<100 {
        if model.sources.first(where: { $0.id == .screenwatch })?.state == .healthy { break }
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.sources.first(where: { $0.id == .screenwatch })?.state == .healthy)
}

@Test
func freshAgentStyleConsumerIngestsCanonicalAlternateAndNotDefault() throws {
    let fixture = try CanonicalScreenwatchFixture(name: "agent-consumer")
    defer { fixture.remove() }
    let alternate = try fixture.makeDaysDirectory(named: "Alternate")
    try fixture.writeCurrentLog(in: alternate, epoch: 1_783_663_210)
    let writer = fixture.repository()
    try writer.saveAlternate(alternate)
    let restartedRepository = fixture.repository()
    let source = try restartedRepository.resolveCanonicalSource()
    let archive = try ScreenwatchArchive(databaseURL: fixture.runtime.databaseURL)

    let result = try archive.ingestToday(
        from: source,
        now: Date(timeIntervalSince1970: 1_783_663_210)
    )

    #expect(result.insertedCount == 1)
    #expect(result.totalRecordsRead == 1)
}

private struct CanonicalScreenwatchFixture {
    let root: URL
    let runtime: RuntimeEnvironment
    let defaults: UserDefaults
    let bookmarkFileURL: URL

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-screenwatch-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runtime = try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", root.path],
            processEnvironment: [:]
        ).environment
        defaults = try #require(UserDefaults(suiteName: runtime.userDefaultsSuiteName!))
        defaults.removePersistentDomain(forName: runtime.userDefaultsSuiteName!)
        bookmarkFileURL = runtime.applicationSupportRoot
            .appendingPathComponent("Zoid Coach", isDirectory: true)
            .appendingPathComponent("screenwatch-source-v1.bookmark", isDirectory: false)
    }

    func repository(
        counter: ScopeCounter = ScopeCounter(),
        isStale: Bool = false,
        rejectResolution: Bool = false
    ) -> ScreenwatchSourceRepository {
        ScreenwatchSourceRepository(
            runtimeEnvironment: runtime,
            bookmarkFileURL: bookmarkFileURL,
            bookmarkAccess: .init(
                create: { Data($0.path.utf8) },
                resolve: { data in
                    if rejectResolution { throw ScreenwatchSourceResolutionError.invalidBookmark }
                    guard let path = String(data: data, encoding: .utf8) else {
                        throw ScreenwatchSourceResolutionError.invalidBookmark
                    }
                    return .init(
                        url: URL(fileURLWithPath: path, isDirectory: true),
                        isStale: isStale
                    )
                },
                startAccess: { _ in counter.start() },
                stopAccess: { _ in counter.stop() }
            ),
            legacyDefaults: [defaults]
        )
    }

    func makeDaysDirectory(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeCurrentLog(in directory: URL, epoch: Int = Int(Date().timeIntervalSince1970) - 5) throws {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = directory.appendingPathComponent(formatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let record = "{\"t\":\"10:00:00\",\"epoch\":\(epoch),\"app\":\"Xcode\",\"window\":\"Workspace\",\"url\":\"\",\"img\":false}\n"
        try Data(record.utf8).write(to: day.appendingPathComponent("log.jsonl"))
    }

    func remove() {
        defaults.removePersistentDomain(forName: runtime.userDefaultsSuiteName!)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ScopeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var stopCount = 0

    var starts: Int { lock.withLock { startCount } }
    var stops: Int { lock.withLock { stopCount } }

    func start() -> Bool {
        lock.withLock { startCount += 1 }
        return true
    }

    func stop() {
        lock.withLock { stopCount += 1 }
    }
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var errors: [String] { lock.withLock { stored } }

    func record(_ error: Error) {
        lock.withLock { stored.append(String(describing: error)) }
    }
}
