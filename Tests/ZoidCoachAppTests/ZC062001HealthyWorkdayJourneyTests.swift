import Foundation
import Testing

@Test
func zc062001ApprovedDayAndFiveHealthRowsRemainReadyAfterReopen() throws {
    let evidence = ZC062001HealthyDayEvidence.healthy
    let first = try evidence.validate()
    let reopened = try JSONDecoder().decode(
        ZC062001HealthyDayEvidence.self,
        from: JSONEncoder().encode(evidence)
    )

    #expect(first == ZC062001HealthyDayEvidence.requiredRows)
    #expect(try reopened.validate() == first)
    #expect(Set(first).count == 5)
}

@Test(arguments: ZC062001FailureBoundary.allCases)
func zc062001HealthBoundaryFailsClosed(boundary: ZC062001FailureBoundary) {
    var evidence = ZC062001HealthyDayEvidence.healthy
    boundary.apply(to: &evidence)

    #expect(throws: ZC062001HealthyDayError.self) {
        _ = try evidence.validate()
    }
}

@Test
func zc062001DuplicateSnapshotSQLAndPrivacyFailuresAreRejected() {
    var duplicate = ZC062001HealthyDayEvidence.healthy
    duplicate.snapshotCount = 2
    #expect(throws: ZC062001HealthyDayError.self) { _ = try duplicate.validate() }

    var sqlFailure = ZC062001HealthyDayEvidence.healthy
    sqlFailure.databaseIntegrity = "query failed"
    #expect(throws: ZC062001HealthyDayError.self) { _ = try sqlFailure.validate() }

    var privacyLeak = ZC062001HealthyDayEvidence.healthy
    privacyLeak.visibleRows[2] += " qa-zc062001-private-window"
    #expect(throws: ZC062001HealthyDayError.self) { _ = try privacyLeak.validate() }
}

struct ZC062001HealthyDayEvidence: Codable, Equatable {
    static let requiredRows = [
        "Planned day - Today's commitments are ready",
        "Apple Reminders - Healthy",
        "Screenwatch - Current and ingested",
        "Zoid 666 Agent - Running",
        "Local database - Healthy",
    ]

    var approvedPlanEntryCount: Int
    var ownedReminderCount: Int
    var snapshotCount: Int
    var snapshotTaskCount: Int
    var remindersState: String
    var screenwatchState: String
    var agentState: String
    var databaseIntegrity: String
    var screenwatchAgeSeconds: Int
    var heartbeatAgeSeconds: Int
    var ingestionLagSeconds: Int
    var visibleRows: [String]
    var containsStaleOrLimitedFallback: Bool

    static let healthy = ZC062001HealthyDayEvidence(
        approvedPlanEntryCount: 1,
        ownedReminderCount: 1,
        snapshotCount: 1,
        snapshotTaskCount: 1,
        remindersState: "authorized",
        screenwatchState: "current",
        agentState: "running",
        databaseIntegrity: "ok",
        screenwatchAgeSeconds: 30,
        heartbeatAgeSeconds: 10,
        ingestionLagSeconds: 0,
        visibleRows: requiredRows,
        containsStaleOrLimitedFallback: false
    )

    func validate() throws -> [String] {
        guard approvedPlanEntryCount == 1,
              ownedReminderCount == 1,
              snapshotCount == 1,
              snapshotTaskCount == 1
        else { throw ZC062001HealthyDayError.durablePlan }
        guard remindersState == "authorized" else {
            throw ZC062001HealthyDayError.reminders
        }
        guard screenwatchState == "current",
              screenwatchAgeSeconds >= 0,
              screenwatchAgeSeconds <= 240,
              ingestionLagSeconds >= 0,
              ingestionLagSeconds <= 240
        else { throw ZC062001HealthyDayError.screenwatch }
        guard agentState == "running",
              heartbeatAgeSeconds >= 0,
              heartbeatAgeSeconds <= 240
        else { throw ZC062001HealthyDayError.agent }
        guard databaseIntegrity == "ok" else {
            throw ZC062001HealthyDayError.database
        }
        guard visibleRows == Self.requiredRows,
              Set(visibleRows).count == 5,
              !containsStaleOrLimitedFallback,
              !visibleRows.joined(separator: "\n").localizedCaseInsensitiveContains("private"),
              !visibleRows.joined(separator: "\n").localizedCaseInsensitiveContains("token")
        else { throw ZC062001HealthyDayError.presentation }
        return visibleRows
    }
}

enum ZC062001FailureBoundary: CaseIterable, Sendable {
    case planMissing
    case remindersUnhealthy
    case screenwatchStale
    case screenwatchMissing
    case heartbeatStale
    case heartbeatMissing
    case ingestionBehind
    case relaunchLoss
    case limitedFallback

    func apply(to evidence: inout ZC062001HealthyDayEvidence) {
        switch self {
        case .planMissing:
            evidence.approvedPlanEntryCount = 0
        case .remindersUnhealthy:
            evidence.remindersState = "denied"
        case .screenwatchStale:
            evidence.screenwatchAgeSeconds = 241
        case .screenwatchMissing:
            evidence.screenwatchState = "missing"
        case .heartbeatStale:
            evidence.heartbeatAgeSeconds = 241
        case .heartbeatMissing:
            evidence.agentState = "missing"
        case .ingestionBehind:
            evidence.ingestionLagSeconds = 241
        case .relaunchLoss:
            evidence.snapshotTaskCount = 0
        case .limitedFallback:
            evidence.containsStaleOrLimitedFallback = true
        }
    }
}

private enum ZC062001HealthyDayError: Error {
    case durablePlan
    case reminders
    case screenwatch
    case agent
    case database
    case presentation
}
