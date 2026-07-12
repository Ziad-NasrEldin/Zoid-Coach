import Darwin
import Foundation
import ZoidCoachCore

enum ScreenwatchSetupSource: String, Equatable, Sendable {
    case defaultLocation
    case alternateFolder
}

enum ScreenwatchSetupHealth: String, Equatable, Sendable {
    case healthy
    case stale
    case missing
    case malformed
    case bookmarkUnavailable
    case accessUnavailable
    case unsafePath
}

enum ScreenwatchSetupContinuation: String, Equatable, Sendable {
    case ready
    case degraded
    case unavailable
}

enum ScreenwatchSetupRepair: String, Equatable, Sendable {
    case none
    case recheck
    case chooseFolder
    case reauthorizeFolder
    case useDefaultLocation
}

struct ScreenwatchSetupStatus: Equatable, Sendable {
    let source: ScreenwatchSetupSource
    let health: ScreenwatchSetupHealth
    let continuation: ScreenwatchSetupContinuation
    let repair: ScreenwatchSetupRepair
    let summary: String
    let evidence: String
    let validRecordCount: Int
}

enum ScreenwatchSetupServiceError: LocalizedError, Equatable, Sendable {
    case unsafePath
    case selectedFolderOutsideQARunRoot
    case selectedItemIsNotDirectory
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .unsafePath:
            "The selected Screenwatch folder is not safe to use."
        case .selectedFolderOutsideQARunRoot:
            "QA Screenwatch folders must remain inside the isolated QA run root."
        case .selectedItemIsNotDirectory:
            "Select the Screenwatch days folder rather than an individual file."
        case .bookmarkCreationFailed:
            "Zoid Coach could not remember access to the selected Screenwatch folder."
        }
    }
}

struct ScreenwatchBookmarkResolution: Sendable {
    let url: URL
    let isStale: Bool
}

struct ScreenwatchBookmarkAccess: Sendable {
    let create: @Sendable (URL) throws -> Data
    let resolve: @Sendable (Data) throws -> ScreenwatchBookmarkResolution
    let startAccess: @Sendable (URL) -> Bool
    let stopAccess: @Sendable (URL) -> Void

    static let foundation = Self(
        create: { url in
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                relativeTo: nil
            )
        },
        resolve: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ScreenwatchBookmarkResolution(url: url, isStale: isStale)
        },
        startAccess: { $0.startAccessingSecurityScopedResource() },
        stopAccess: { $0.stopAccessingSecurityScopedResource() }
    )
}

actor ScreenwatchSetupService {
    static let bookmarkDefaultsKey = "screenwatch.setup.alternate-days-bookmark.v1"

    private let runtimeEnvironment: RuntimeEnvironment
    private let fileManager: FileManager
    private let bookmarkAccess: ScreenwatchBookmarkAccess
    private let bookmarkStore: ScreenwatchBookmarkStore
    private let calendar: Calendar
    private let staleThreshold: TimeInterval

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        fileManager: FileManager = .default,
        bookmarkAccess: ScreenwatchBookmarkAccess = .foundation,
        calendar: Calendar = .current,
        staleThreshold: TimeInterval = 30
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.fileManager = fileManager
        self.bookmarkAccess = bookmarkAccess
        bookmarkStore = ScreenwatchBookmarkStore(
            defaults: runtimeEnvironment.makeUserDefaults(),
            key: Self.bookmarkDefaultsKey
        )
        self.calendar = calendar
        self.staleThreshold = max(0, staleThreshold)
    }

    init(
        runtimeEnvironment: RuntimeEnvironment,
        fileManager: FileManager = .default,
        bookmarkStore: ScreenwatchBookmarkStore,
        bookmarkAccess: ScreenwatchBookmarkAccess = .foundation,
        calendar: Calendar = .current,
        staleThreshold: TimeInterval = 30
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.fileManager = fileManager
        self.bookmarkAccess = bookmarkAccess
        self.bookmarkStore = bookmarkStore
        self.calendar = calendar
        self.staleThreshold = max(0, staleThreshold)
    }

    func inspect(now: Date = Date()) -> ScreenwatchSetupStatus {
        guard let bookmark = bookmarkStore.load() else {
            return inspectDirectory(
                runtimeEnvironment.screenwatchDirectory,
                source: .defaultLocation,
                now: now
            )
        }
        let resolution: ScreenwatchBookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(bookmark)
        } catch {
            return Self.bookmarkUnavailableStatus
        }
        guard isSafeDirectory(resolution.url), isAllowedByRuntime(resolution.url) else {
            return Self.unsafeAlternateStatus
        }
        let didStartAccess = bookmarkAccess.startAccess(resolution.url)
        defer {
            if didStartAccess { bookmarkAccess.stopAccess(resolution.url) }
        }
        if resolution.isStale {
            do {
                bookmarkStore.save(try bookmarkAccess.create(resolution.url))
            } catch {
                return Self.bookmarkUnavailableStatus
            }
        }
        return inspectDirectory(resolution.url, source: .alternateFolder, now: now)
    }

    func recheck(now: Date = Date()) -> ScreenwatchSetupStatus {
        inspect(now: now)
    }

    func selectAlternateDaysDirectory(
        _ url: URL,
        now: Date = Date()
    ) throws -> ScreenwatchSetupStatus {
        guard isSafeDirectory(url) else {
            throw ScreenwatchSetupServiceError.unsafePath
        }
        guard isAllowedByRuntime(url) else {
            throw ScreenwatchSetupServiceError.selectedFolderOutsideQARunRoot
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            throw ScreenwatchSetupServiceError.selectedItemIsNotDirectory
        }
        do {
            bookmarkStore.save(try bookmarkAccess.create(url))
        } catch {
            throw ScreenwatchSetupServiceError.bookmarkCreationFailed
        }
        return inspect(now: now)
    }

    func useDefaultLocation(now: Date = Date()) -> ScreenwatchSetupStatus {
        bookmarkStore.remove()
        return inspectDirectory(
            runtimeEnvironment.screenwatchDirectory,
            source: .defaultLocation,
            now: now
        )
    }

    private func inspectDirectory(
        _ daysDirectory: URL,
        source: ScreenwatchSetupSource,
        now: Date
    ) -> ScreenwatchSetupStatus {
        guard isSafeDirectory(daysDirectory), isAllowedByRuntime(daysDirectory) else {
            return source == .alternateFolder
                ? Self.unsafeAlternateStatus
                : Self.unsafeDefaultStatus
        }
        let logURL = dailyLogURL(daysDirectory: daysDirectory, date: now)
        guard isSafeDirectory(logURL) else {
            return source == .alternateFolder
                ? Self.unsafeAlternateStatus
                : Self.unsafeDefaultStatus
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: logURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return ScreenwatchSetupStatus(
                source: source,
                health: .missing,
                continuation: .degraded,
                repair: source == .defaultLocation ? .chooseFolder : .recheck,
                summary: "Today’s Screenwatch telemetry stream was not found.",
                evidence: "Planning remains available without behavior coaching.",
                validRecordCount: 0
            )
        }
        do {
            let validation = try validateJSONL(at: logURL)
            guard validation.invalidRecordCount == 0, validation.validRecordCount > 0,
                  let latestEpoch = validation.latestEpoch else {
                return ScreenwatchSetupStatus(
                    source: source,
                    health: .malformed,
                    continuation: .degraded,
                    repair: .recheck,
                    summary: "Screenwatch telemetry does not match the expected schema.",
                    evidence: "Validation failed without displaying captured titles or URLs.",
                    validRecordCount: validation.validRecordCount
                )
            }
            let age = max(0, now.timeIntervalSince1970 - TimeInterval(latestEpoch))
            if age > staleThreshold {
                return ScreenwatchSetupStatus(
                    source: source,
                    health: .stale,
                    continuation: .degraded,
                    repair: .recheck,
                    summary: "Screenwatch telemetry is connected but not current.",
                    evidence: "Schema-valid local records were found.",
                    validRecordCount: validation.validRecordCount
                )
            }
            return ScreenwatchSetupStatus(
                source: source,
                health: .healthy,
                continuation: .ready,
                repair: .none,
                summary: "Screenwatch telemetry is connected and current.",
                evidence: "Schema-valid local records were found.",
                validRecordCount: validation.validRecordCount
            )
        } catch {
            return ScreenwatchSetupStatus(
                source: source,
                health: .accessUnavailable,
                continuation: .unavailable,
                repair: source == .defaultLocation ? .chooseFolder : .reauthorizeFolder,
                summary: "Screenwatch telemetry could not be read safely.",
                evidence: "Access failed without displaying captured content or file locations.",
                validRecordCount: 0
            )
        }
    }

    private func validateJSONL(at url: URL) throws -> ScreenwatchSchemaValidation {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var trailing = Data()
        var validCount = 0
        var invalidCount = 0
        var latestEpoch: Int?
        let decoder = JSONDecoder()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            trailing.append(chunk)
            let endsInNewline = trailing.last == 0x0A
            var lines = trailing.split(separator: 0x0A, omittingEmptySubsequences: true)
            if !endsInNewline, let partial = lines.popLast() {
                trailing = Data(partial)
            } else {
                trailing.removeAll(keepingCapacity: true)
            }
            for line in lines {
                if let record = try? decoder.decode(
                    PrivacySafeScreenwatchRecord.self,
                    from: Data(line)
                ) {
                    validCount += 1
                    latestEpoch = max(latestEpoch ?? record.epoch, record.epoch)
                } else {
                    invalidCount += 1
                }
            }
        }
        return ScreenwatchSchemaValidation(
            validRecordCount: validCount,
            invalidRecordCount: invalidCount,
            latestEpoch: latestEpoch
        )
    }

    private func dailyLogURL(daysDirectory: URL, date: Date) -> URL {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return daysDirectory
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("log.jsonl", isDirectory: false)
    }

    private func isAllowedByRuntime(_ url: URL) -> Bool {
        guard case let .qa(runRoot) = runtimeEnvironment.mode else { return true }
        let candidate = canonicalPath(url)
        let root = canonicalPath(runRoot)
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func isSafeDirectory(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/") else { return false }
        let normalizedPath = macOSTemporaryDirectoryAliasResolvedPath(url)
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in normalizedPath.split(separator: "/").map(String.init) {
            current.appendPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: current.path) else { continue }
            guard let values = try? current.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ), values.isSymbolicLink != true else {
                return false
            }
        }
        return true
    }

    private func canonicalPath(_ url: URL) -> String {
        macOSTemporaryDirectoryAliasResolvedPath(url.resolvingSymlinksInPath())
    }

    private func macOSTemporaryDirectoryAliasResolvedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path == "/var" || path.hasPrefix("/var/") else { return path }
        return "/private" + path
    }

    private static let bookmarkUnavailableStatus = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .bookmarkUnavailable,
        continuation: .unavailable,
        repair: .reauthorizeFolder,
        summary: "The saved Screenwatch folder permission is no longer available.",
        evidence: "Choose the folder again to restore behavior coaching.",
        validRecordCount: 0
    )

    private static let unsafeAlternateStatus = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .unsafePath,
        continuation: .unavailable,
        repair: .reauthorizeFolder,
        summary: "The saved Screenwatch folder cannot be used safely.",
        evidence: "Choose a direct, non-symbolic folder inside the allowed runtime.",
        validRecordCount: 0
    )

    private static let unsafeDefaultStatus = ScreenwatchSetupStatus(
        source: .defaultLocation,
        health: .unsafePath,
        continuation: .unavailable,
        repair: .chooseFolder,
        summary: "The default Screenwatch folder cannot be used safely.",
        evidence: "Choose a direct, non-symbolic Screenwatch days folder.",
        validRecordCount: 0
    )
}

final class ScreenwatchBookmarkStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Data? {
        lock.withLock { defaults.data(forKey: key) }
    }

    func save(_ data: Data) {
        lock.withLock { defaults.set(data, forKey: key) }
    }

    func remove() {
        lock.withLock { defaults.removeObject(forKey: key) }
    }
}

private struct ScreenwatchSchemaValidation {
    let validRecordCount: Int
    let invalidRecordCount: Int
    let latestEpoch: Int?
}

private struct PrivacySafeScreenwatchRecord: Decodable {
    let epoch: Int

    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case epoch
        case application = "app"
        case windowTitle = "window"
        case pageURL = "url"
        case hasImage = "img"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        _ = try values.decode(String.self, forKey: .timestamp)
        epoch = try values.decode(Int.self, forKey: .epoch)
        _ = try values.decode(String.self, forKey: .application)
        _ = try values.decode(String.self, forKey: .windowTitle)
        _ = try values.decode(String.self, forKey: .pageURL)
        _ = try values.decode(Bool.self, forKey: .hasImage)
    }
}
