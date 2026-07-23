import Foundation
import Testing

@Test(arguments: ZC062002OutagePhase.allCases)
func zc062002ActiveTechnicalTaskSurvivesIsolatedScreenwatchOutage(
    phase: ZC062002OutagePhase
) throws {
    let evidence = ZC062002OutageEvidence.valid(phase)
    #expect(try evidence.validate() == phase)

    let reopened = try JSONDecoder().decode(
        ZC062002OutageEvidence.self,
        from: JSONEncoder().encode(evidence)
    )
    #expect(try reopened.validate() == phase)
}

@Test(arguments: ZC062002FailureBoundary.allCases)
func zc062002OutageBoundariesFailClosed(boundary: ZC062002FailureBoundary) {
    var evidence = ZC062002OutageEvidence.valid(.stale)
    boundary.apply(to: &evidence)
    #expect(throws: ZC062002OutageError.self) {
        _ = try evidence.validate()
    }
}

@Test
func zc062002SQLDuplicatePrivacyAndRealPathFailuresAreRejected() {
    var sql = ZC062002OutageEvidence.valid(.missing)
    sql.databaseIntegrity = "query failed"
    #expect(throws: ZC062002OutageError.self) { _ = try sql.validate() }

    var duplicate = ZC062002OutageEvidence.valid(.stale)
    duplicate.snapshotCount = 2
    #expect(throws: ZC062002OutageError.self) { _ = try duplicate.validate() }

    var privacy = ZC062002OutageEvidence.valid(.fresh)
    privacy.visibleText += " qa-zc062002-private-window"
    #expect(throws: ZC062002OutageError.self) { _ = try privacy.validate() }

    var realPath = ZC062002OutageEvidence.valid(.missing)
    realPath.screenwatchRoot = "~/screenwatch/days"
    #expect(throws: ZC062002OutageError.self) { _ = try realPath.validate() }
}

enum ZC062002OutagePhase: String, Codable, CaseIterable, Sendable {
    case fresh
    case stale
    case missing
}

private struct ZC062002OutageEvidence: Codable {
    var phase: ZC062002OutagePhase
    var qaRoot: String
    var databasePath: String
    var screenwatchRoot: String
    var taskState: String
    var technicalContext: String
    var openIntervalCount: Int
    var snapshotCount: Int
    var snapshotActiveTaskID: String?
    var baselineIngestionCount: Int
    var advancedIngestionCount: Int
    var streamAgeSeconds: Int?
    var databaseIntegrity: String
    var visibleText: String

    static func valid(_ phase: ZC062002OutagePhase) -> Self {
        let root = "/private/tmp/zoid-666-zc062002-tests"
        return Self(
            phase: phase,
            qaRoot: root,
            databasePath: "\(root)/Application Support/Zoid 666/zoid-coach.sqlite",
            screenwatchRoot: "\(root)/Screenwatch/days",
            taskState: "active",
            technicalContext: "technical",
            openIntervalCount: 1,
            snapshotCount: 1,
            snapshotActiveTaskID: "qa-zc062002-active-technical",
            baselineIngestionCount: 1,
            advancedIngestionCount: phase == .fresh ? 1 : 0,
            streamAgeSeconds: phase == .missing ? nil : phase == .stale ? 241 : 10,
            databaseIntegrity: "ok",
            visibleText: "ACTIVE WORK. Technical task. The active task timer continues locally."
        )
    }

    func validate() throws -> ZC062002OutagePhase {
        guard qaRoot.hasPrefix("/private/tmp/zoid-666-zc062002-"),
              databasePath == "\(qaRoot)/Application Support/Zoid 666/zoid-coach.sqlite",
              screenwatchRoot == "\(qaRoot)/Screenwatch/days",
              !screenwatchRoot.contains("~/screenwatch"),
              !screenwatchRoot.contains("/Users/")
        else { throw ZC062002OutageError.ownership }
        guard taskState == "active",
              technicalContext == "technical",
              openIntervalCount == 1,
              snapshotActiveTaskID == "qa-zc062002-active-technical"
        else { throw ZC062002OutageError.activeTask }
        guard snapshotCount == 1, databaseIntegrity == "ok" else {
            throw ZC062002OutageError.database
        }
        guard baselineIngestionCount == 1 else {
            throw ZC062002OutageError.baseline
        }
        switch phase {
        case .fresh:
            guard advancedIngestionCount == 1,
                  streamAgeSeconds.map({ (0...240).contains($0) }) == true
            else { throw ZC062002OutageError.sourceState }
        case .stale:
            guard advancedIngestionCount == 0,
                  streamAgeSeconds.map({ $0 > 240 }) == true
            else { throw ZC062002OutageError.sourceState }
        case .missing:
            guard advancedIngestionCount == 0, streamAgeSeconds == nil else {
                throw ZC062002OutageError.sourceState
            }
        }
        guard !visibleText.localizedCaseInsensitiveContains("qa-zc062002-private"),
              !visibleText.localizedCaseInsensitiveContains("token")
        else { throw ZC062002OutageError.presentation }
        return phase
    }
}

enum ZC062002FailureBoundary: CaseIterable, Sendable {
    case activeTaskLost
    case intervalClosed
    case wrongDatabase
    case wrongSource
    case staleAcceptedAsFresh
    case freshAcceptedAsStale
    case baselineMissing
    case relaunchSnapshotLoss

    fileprivate func apply(to evidence: inout ZC062002OutageEvidence) {
        switch self {
        case .activeTaskLost:
            evidence.taskState = "paused"
        case .intervalClosed:
            evidence.openIntervalCount = 0
        case .wrongDatabase:
            evidence.databasePath = "/private/tmp/wrong.sqlite"
        case .wrongSource:
            evidence.screenwatchRoot = "/private/tmp/other/days"
        case .staleAcceptedAsFresh:
            evidence.phase = .fresh
        case .freshAcceptedAsStale:
            evidence.streamAgeSeconds = 10
        case .baselineMissing:
            evidence.baselineIngestionCount = 0
        case .relaunchSnapshotLoss:
            evidence.snapshotActiveTaskID = nil
        }
    }
}

private enum ZC062002OutageError: Error {
    case ownership
    case activeTask
    case database
    case baseline
    case sourceState
    case presentation
}
