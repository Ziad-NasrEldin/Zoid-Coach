import Foundation
import Testing

@Test(arguments: ZC062004SourcePhase.allCases)
func zc062004ManualTrackingAdvancesThroughIsolatedOutageAndRelaunch(
    phase: ZC062004SourcePhase
) throws {
    let evidence = ZC062004TrackingEvidence.valid(phase)
    #expect(try evidence.validate() == phase)

    let relaunched = try JSONDecoder().decode(
        ZC062004TrackingEvidence.self,
        from: JSONEncoder().encode(evidence)
    )
    #expect(try relaunched.validate() == phase)
}

@Test(arguments: ZC062004Boundary.allCases)
func zc062004TrackingBoundariesFailClosed(boundary: ZC062004Boundary) {
    var evidence = ZC062004TrackingEvidence.valid(.missing)
    boundary.apply(to: &evidence)
    #expect(throws: ZC062004Error.self) { _ = try evidence.validate() }
}

@Test
func zc062004SQLPrivacyDuplicateSnapshotAndRealPathFailuresAreRejected() {
    var sql = ZC062004TrackingEvidence.valid(.stale)
    sql.databaseIntegrity = "schema failed"
    #expect(throws: ZC062004Error.self) { _ = try sql.validate() }

    var privacy = ZC062004TrackingEvidence.valid(.missing)
    privacy.visibleText += " qa-zc062004-private-window"
    #expect(throws: ZC062004Error.self) { _ = try privacy.validate() }

    var duplicate = ZC062004TrackingEvidence.valid(.fresh)
    duplicate.snapshotCount = 2
    #expect(throws: ZC062004Error.self) { _ = try duplicate.validate() }

    var realPath = ZC062004TrackingEvidence.valid(.stale)
    realPath.screenwatchRoot = "~/screenwatch/days"
    #expect(throws: ZC062004Error.self) { _ = try realPath.validate() }
}

private enum ZC062004SourcePhase: String, Codable, CaseIterable, Sendable {
    case fresh
    case stale
    case missing
}

private struct ZC062004TrackingEvidence: Codable {
    var phase: ZC062004SourcePhase
    var qaRoot: String
    var databasePath: String
    var screenwatchRoot: String
    var taskID: String
    var sourceKind: String
    var taskState: String
    var openIntervalCount: Int
    var intervalIDBefore: Int
    var intervalIDAfter: Int
    var intervalIDAfterRelaunch: Int
    var initialElapsedMinutes: Int
    var advancedElapsedMinutes: Int
    var relaunchedElapsedMinutes: Int
    var snapshotCount: Int
    var snapshotActiveTaskID: String?
    var snapshotElapsedMinutes: Int
    var sourceState: String
    var invalidReminderRowsRemaining: Int
    var databaseIntegrity: String
    var visibleText: String

    static func valid(_ phase: ZC062004SourcePhase) -> Self {
        let root = "/private/tmp/zoid-666-zc062004-tests"
        return Self(
            phase: phase,
            qaRoot: root,
            databasePath: "\(root)/Application Support/Zoid 666/zoid-coach.sqlite",
            screenwatchRoot: "\(root)/Screenwatch/days",
            taskID: "qa-zc062004-active-technical",
            sourceKind: "local",
            taskState: "active",
            openIntervalCount: 1,
            intervalIDBefore: 42,
            intervalIDAfter: 42,
            intervalIDAfterRelaunch: 42,
            initialElapsedMinutes: 14,
            advancedElapsedMinutes: 19,
            relaunchedElapsedMinutes: 19,
            snapshotCount: 1,
            snapshotActiveTaskID: "qa-zc062004-active-technical",
            snapshotElapsedMinutes: 19,
            sourceState: phase == .fresh ? "current" : "limited",
            invalidReminderRowsRemaining: 0,
            databaseIntegrity: "ok",
            visibleText: "Technical task. QA ZC-062-004 active technical task. Open-ended session. 19 minutes tracked. Pause QA ZC-062-004 active technical task. Complete QA ZC-062-004 active technical task."
        )
    }

    func validate() throws -> ZC062004SourcePhase {
        guard qaRoot.hasPrefix("/private/tmp/zoid-666-zc062004-"),
              databasePath == "\(qaRoot)/Application Support/Zoid 666/zoid-coach.sqlite",
              screenwatchRoot == "\(qaRoot)/Screenwatch/days",
              !screenwatchRoot.contains("~/screenwatch"),
              !screenwatchRoot.contains("/Users/")
        else { throw ZC062004Error.ownership }
        guard databaseIntegrity == "ok", snapshotCount == 1 else {
            throw ZC062004Error.database
        }
        guard taskID == "qa-zc062004-active-technical",
              sourceKind == "local",
              taskState == "active",
              invalidReminderRowsRemaining == 0,
              snapshotActiveTaskID == taskID
        else { throw ZC062004Error.task }
        guard openIntervalCount == 1,
              intervalIDBefore == intervalIDAfter,
              intervalIDAfter == intervalIDAfterRelaunch
        else { throw ZC062004Error.interval }
        guard advancedElapsedMinutes > initialElapsedMinutes,
              relaunchedElapsedMinutes == advancedElapsedMinutes,
              snapshotElapsedMinutes == advancedElapsedMinutes
        else { throw ZC062004Error.elapsed }
        guard sourceState == (phase == .fresh ? "current" : "limited") else {
            throw ZC062004Error.source
        }
        let required = [
            "qa zc-062-004 active technical task",
            "open-ended session",
            "\(advancedElapsedMinutes) minutes tracked",
            "pause qa zc-062-004 active technical task",
            "complete qa zc-062-004 active technical task",
        ]
        let normalized = visibleText.lowercased()
        guard required.allSatisfy(normalized.contains),
              !normalized.contains("qa-zc062004-private"),
              !normalized.contains("private.invalid")
        else { throw ZC062004Error.presentation }
        return phase
    }
}

private enum ZC062004Boundary: CaseIterable, Sendable {
    case wrongDatabase
    case wrongSource
    case invalidReminderBootstrap
    case duplicateIntervals
    case intervalReplaced
    case elapsedFreeze
    case elapsedReset
    case taskLoss
    case staleAcceptedAsFresh
    case controlsInconsistent
    case relaunchSnapshotLoss

    func apply(to evidence: inout ZC062004TrackingEvidence) {
        switch self {
        case .wrongDatabase: evidence.databasePath = "/private/tmp/wrong.sqlite"
        case .wrongSource: evidence.screenwatchRoot = "/private/tmp/other/days"
        case .invalidReminderBootstrap: evidence.sourceKind = "reminders"
        case .duplicateIntervals: evidence.openIntervalCount = 2
        case .intervalReplaced: evidence.intervalIDAfter = 43
        case .elapsedFreeze: evidence.advancedElapsedMinutes = evidence.initialElapsedMinutes
        case .elapsedReset: evidence.relaunchedElapsedMinutes = 0
        case .taskLoss: evidence.taskState = "paused"
        case .staleAcceptedAsFresh: evidence.sourceState = "current"
        case .controlsInconsistent: evidence.visibleText = "19 minutes tracked"
        case .relaunchSnapshotLoss: evidence.snapshotActiveTaskID = nil
        }
    }
}

private enum ZC062004Error: Error {
    case ownership
    case database
    case task
    case interval
    case elapsed
    case source
    case presentation
}
