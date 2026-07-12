import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

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
        case .unsafePath: "The selected Screenwatch folder is not safe to use."
        case .selectedFolderOutsideQARunRoot: "QA Screenwatch folders must remain inside the isolated QA run root."
        case .selectedItemIsNotDirectory: "Select the Screenwatch days folder rather than an individual file."
        case .bookmarkCreationFailed: "Zoid 666 could not remember access to the selected Screenwatch folder."
        }
    }
}

actor ScreenwatchSetupService {
    static let bookmarkDefaultsKey = ScreenwatchSourceRepository.legacyBookmarkDefaultsKey

    private let repository: ScreenwatchSourceRepository
    private let calendar: Calendar
    private let staleThreshold: TimeInterval

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        calendar: Calendar = .current,
        staleThreshold: TimeInterval = 30
    ) {
        repository = ScreenwatchSourceRepository(runtimeEnvironment: runtimeEnvironment)
        self.calendar = calendar
        self.staleThreshold = max(0, staleThreshold)
    }

    init(
        repository: ScreenwatchSourceRepository,
        calendar: Calendar = .current,
        staleThreshold: TimeInterval = 30
    ) {
        self.repository = repository
        self.calendar = calendar
        self.staleThreshold = max(0, staleThreshold)
    }

    func inspect(now: Date = Date()) -> ScreenwatchSetupStatus {
        do {
            let lease = try repository.resolveCanonicalSource()
            return inspectDirectory(lease, now: now)
        } catch let error as ScreenwatchSourceResolutionError {
            return status(for: error, hasAlternateSelection: repository.hasAlternateSelection)
        } catch {
            return Self.bookmarkUnavailableStatus
        }
    }

    func recheck(now: Date = Date()) -> ScreenwatchSetupStatus {
        inspect(now: now)
    }

    func selectAlternateDaysDirectory(
        _ url: URL,
        now: Date = Date()
    ) throws -> ScreenwatchSetupStatus {
        do {
            try repository.saveAlternate(url)
        } catch ScreenwatchSourceResolutionError.outsideQARunRoot {
            throw ScreenwatchSetupServiceError.selectedFolderOutsideQARunRoot
        } catch ScreenwatchSourceResolutionError.notDirectory,
                ScreenwatchSourceResolutionError.missingDirectory {
            throw ScreenwatchSetupServiceError.selectedItemIsNotDirectory
        } catch ScreenwatchSourceResolutionError.unsafePath {
            throw ScreenwatchSetupServiceError.unsafePath
        } catch {
            throw ScreenwatchSetupServiceError.bookmarkCreationFailed
        }
        return inspect(now: now)
    }

    func useDefaultLocation(now: Date = Date()) -> ScreenwatchSetupStatus {
        do {
            try repository.clearAlternate()
            return inspect(now: now)
        } catch {
            return ScreenwatchSetupStatus(
                source: .defaultLocation,
                health: .accessUnavailable,
                continuation: .unavailable,
                repair: .chooseFolder,
                summary: "The Screenwatch source choice could not be updated safely.",
                evidence: "No captured content or file location was displayed.",
                validRecordCount: 0
            )
        }
    }

    private func inspectDirectory(
        _ lease: ScreenwatchDirectoryLease,
        now: Date
    ) -> ScreenwatchSetupStatus {
        let source: ScreenwatchSetupSource = lease.source == .alternateBookmark
            ? .alternateFolder
            : .defaultLocation
        let components = [dayKey(for: now), "log.jsonl"]
        let data: Data
        do {
            data = try lease.data(at: components)
        } catch ScreenwatchSourceResolutionError.missingDirectory {
            return ScreenwatchSetupStatus(
                source: source,
                health: .missing,
                continuation: .degraded,
                repair: .recheck,
                summary: "No Screenwatch telemetry was found for today yet.",
                evidence: "The selected local source is available, but today's log is missing.",
                validRecordCount: 0
            )
        } catch ScreenwatchSourceResolutionError.unsafePath,
                ScreenwatchSourceResolutionError.notDirectory,
                ScreenwatchSourceResolutionError.notRegularFile {
            return source == .alternateFolder
                ? Self.unsafeAlternateStatus
                : ScreenwatchSetupStatus(
                    source: .defaultLocation,
                    health: .unsafePath,
                    continuation: .unavailable,
                    repair: .chooseFolder,
                    summary: "The default Screenwatch folder cannot be used safely.",
                    evidence: "Choose a direct, non-symbolic Screenwatch days folder.",
                    validRecordCount: 0
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
        do {
            let validation = try validateJSONL(data)
            guard validation.invalidRecordCount == 0,
                  validation.validRecordCount > 0,
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

    private func status(
        for error: ScreenwatchSourceResolutionError,
        hasAlternateSelection: Bool
    ) -> ScreenwatchSetupStatus {
        switch error {
        case .staleBookmark, .invalidBookmark, .bookmarkStoreCorrupt:
            Self.bookmarkUnavailableStatus
        case .outsideQARunRoot, .unsafePath, .invalidRelativePath:
            Self.unsafeAlternateStatus
        case .missingDirectory:
            ScreenwatchSetupStatus(
                source: hasAlternateSelection ? .alternateFolder : .defaultLocation,
                health: .missing,
                continuation: hasAlternateSelection ? .unavailable : .degraded,
                repair: hasAlternateSelection ? .reauthorizeFolder : .chooseFolder,
                summary: hasAlternateSelection
                    ? "The selected Screenwatch folder is no longer available."
                    : "No Screenwatch telemetry was found for today yet.",
                evidence: hasAlternateSelection
                    ? "Choose the days folder again or return to the default location."
                    : "Choose the days folder or continue in degraded mode.",
                validRecordCount: 0
            )
        case .securityScopeUnavailable, .notDirectory, .notRegularFile, .ioFailure:
            ScreenwatchSetupStatus(
                source: .alternateFolder,
                health: .accessUnavailable,
                continuation: .unavailable,
                repair: .reauthorizeFolder,
                summary: "The selected Screenwatch folder could not be accessed safely.",
                evidence: "Choose the folder again or return to the default location.",
                validRecordCount: 0
            )
        }
    }

    private func validateJSONL(_ data: Data) throws -> ScreenwatchSchemaValidation {
        var validCount = 0
        var invalidCount = 0
        var latestEpoch: Int?
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let record = try? decoder.decode(PrivacySafeScreenwatchRecord.self, from: Data(line)),
               record.epoch > 0,
               !record.app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !record.window.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validCount += 1
                latestEpoch = max(latestEpoch ?? record.epoch, record.epoch)
            } else {
                invalidCount += 1
            }
        }
        return .init(
            validRecordCount: validCount,
            invalidRecordCount: invalidCount,
            latestEpoch: latestEpoch
        )
    }

    private func dayKey(for date: Date) -> String {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static let bookmarkUnavailableStatus = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .bookmarkUnavailable,
        continuation: .unavailable,
        repair: .reauthorizeFolder,
        summary: "The saved Screenwatch folder authorization is no longer usable.",
        evidence: "Choose the folder again or return to the default location.",
        validRecordCount: 0
    )

    private static let unsafeAlternateStatus = ScreenwatchSetupStatus(
        source: .alternateFolder,
        health: .unsafePath,
        continuation: .unavailable,
        repair: .reauthorizeFolder,
        summary: "The selected Screenwatch folder cannot be used safely.",
        evidence: "Choose a direct, non-symbolic folder inside the allowed runtime.",
        validRecordCount: 0
    )
}

private struct ScreenwatchSchemaValidation {
    let validRecordCount: Int
    let invalidRecordCount: Int
    let latestEpoch: Int?
}

private struct PrivacySafeScreenwatchRecord: Decodable {
    let epoch: Int
    let app: String
    let window: String
    let url: String
    let img: Bool
}
