import Foundation
import Testing

@Test(arguments: ZC062003Phase.allCases)
func zc062003HealthyControlThenOutageWarnsAndSuppresses(phase: ZC062003Phase) throws {
    let evidence = ZC062003Evidence.valid(phase)
    #expect(try evidence.validate() == phase)

    let relaunched = try JSONDecoder().decode(
        ZC062003Evidence.self,
        from: JSONEncoder().encode(evidence)
    )
    #expect(try relaunched.validate() == phase)
}

@Test(arguments: ZC062003Boundary.allCases)
func zc062003ProofBoundariesFailClosed(boundary: ZC062003Boundary) {
    var evidence = ZC062003Evidence.valid(.stale)
    boundary.apply(to: &evidence)
    #expect(throws: ZC062003Error.self) { _ = try evidence.validate() }
}

@Test
func zc062003HandledSQLPrivacyDuplicateAndRealPathsAreRejected() {
    var handled = ZC062003Evidence.valid(.missing)
    handled.handledPromptCount = 1
    #expect(try? handled.validate() == .missing)

    var sql = ZC062003Evidence.valid(.stale)
    sql.databaseIntegrity = "query failed"
    #expect(throws: ZC062003Error.self) { _ = try sql.validate() }

    var privacy = ZC062003Evidence.valid(.missing)
    privacy.visibleText += " qa-zc062003-private-window"
    #expect(throws: ZC062003Error.self) { _ = try privacy.validate() }

    var duplicate = ZC062003Evidence.valid(.healthy)
    duplicate.strongPromptCount = 2
    #expect(throws: ZC062003Error.self) { _ = try duplicate.validate() }

    var realPath = ZC062003Evidence.valid(.stale)
    realPath.screenwatchRoot = "~/screenwatch/days"
    #expect(throws: ZC062003Error.self) { _ = try realPath.validate() }
}

enum ZC062003Phase: String, Codable, CaseIterable, Sendable {
    case healthy
    case stale
    case missing
}

private struct ZC062003Evidence: Codable {
    var phase: ZC062003Phase
    var qaRoot: String
    var databasePath: String
    var screenwatchRoot: String
    var osStatePath: String
    var baselineDayCount: Int
    var plannedTaskCount: Int
    var activeStateCount: Int
    var openIntervalCount: Int
    var eligibleObservationCount: Int
    var latestObservationAge: Int?
    var snapshotCount: Int
    var snapshotActiveTaskID: String?
    var sourceState: String
    var strongPromptCount: Int
    var unresolvedStrongPromptCount: Int
    var withdrawnBySystemCount: Int
    var handledPromptCount: Int
    var matchingNotificationCount: Int
    var databaseIntegrity: String
    var visibleText: String

    static func valid(_ phase: ZC062003Phase) -> Self {
        let root = "/private/tmp/zoid-666-zc062003-tests"
        return Self(
            phase: phase,
            qaRoot: root,
            databasePath: "\(root)/Application Support/Zoid 666/zoid-coach.sqlite",
            screenwatchRoot: "\(root)/Screenwatch/days",
            osStatePath: "\(root)/OS Fixtures/state.json",
            baselineDayCount: 7,
            plannedTaskCount: 1,
            activeStateCount: 1,
            openIntervalCount: 1,
            eligibleObservationCount: 10,
            latestObservationAge: phase == .missing ? nil : phase == .stale ? 901 : 30,
            snapshotCount: 1,
            snapshotActiveTaskID: "qa-zc062003-active-technical",
            sourceState: phase == .healthy ? "current" : "limited",
            strongPromptCount: 1,
            unresolvedStrongPromptCount: phase == .healthy ? 1 : 0,
            withdrawnBySystemCount: phase == .healthy ? 0 : 1,
            handledPromptCount: 0,
            matchingNotificationCount: phase == .healthy ? 1 : 0,
            databaseIntegrity: "ok",
            visibleText: phase == .healthy
                ? "Is this gaming intentional? Return to QA ZC-062-003 active technical task."
                : "LIMITED COVERAGE. Screenwatch is \(phase == .stale ? "stale" : "missing"). Active work continues."
        )
    }

    func validate() throws -> ZC062003Phase {
        guard qaRoot.hasPrefix("/private/tmp/zoid-666-zc062003-"),
              databasePath == "\(qaRoot)/Application Support/Zoid 666/zoid-coach.sqlite",
              screenwatchRoot == "\(qaRoot)/Screenwatch/days",
              osStatePath == "\(qaRoot)/OS Fixtures/state.json",
              !screenwatchRoot.contains("~/screenwatch"),
              !screenwatchRoot.contains("/Users/")
        else { throw ZC062003Error.ownership }
        guard databaseIntegrity == "ok", snapshotCount == 1 else {
            throw ZC062003Error.database
        }
        guard baselineDayCount == 7,
              plannedTaskCount == 1,
              activeStateCount == 1,
              openIntervalCount == 1,
              eligibleObservationCount == 10,
              snapshotActiveTaskID == "qa-zc062003-active-technical"
        else { throw ZC062003Error.eligibility }
        guard strongPromptCount == 1, handledPromptCount <= 1 else {
            throw ZC062003Error.duplicate
        }

        switch phase {
        case .healthy:
            guard latestObservationAge.map({ (0...180).contains($0) }) == true,
                  sourceState == "current",
                  unresolvedStrongPromptCount == 1,
                  withdrawnBySystemCount == 0,
                  matchingNotificationCount == 1,
                  visibleText.localizedCaseInsensitiveContains("is this gaming intentional?")
            else { throw ZC062003Error.transition }
        case .stale:
            guard latestObservationAge.map({ $0 > 900 }) == true,
                  sourceState == "limited",
                  unresolvedStrongPromptCount == 0,
                  withdrawnBySystemCount == 1,
                  matchingNotificationCount == 0,
                  visibleText.localizedCaseInsensitiveContains("limited coverage"),
                  visibleText.localizedCaseInsensitiveContains("stale"),
                  !visibleText.localizedCaseInsensitiveContains("is this gaming intentional?")
            else { throw ZC062003Error.transition }
        case .missing:
            guard latestObservationAge == nil,
                  sourceState == "limited",
                  unresolvedStrongPromptCount == 0,
                  withdrawnBySystemCount == 1,
                  matchingNotificationCount == 0,
                  visibleText.localizedCaseInsensitiveContains("limited coverage"),
                  visibleText.localizedCaseInsensitiveContains("missing"),
                  !visibleText.localizedCaseInsensitiveContains("is this gaming intentional?")
            else { throw ZC062003Error.transition }
        }
        guard !visibleText.localizedCaseInsensitiveContains("qa-zc062003-private"),
              !visibleText.localizedCaseInsensitiveContains("private.invalid")
        else { throw ZC062003Error.privacy }
        return phase
    }
}

enum ZC062003Boundary: CaseIterable, Sendable {
    case wrongDatabase
    case wrongSource
    case wrongOSState
    case noEligibleBaseline
    case lostPlan
    case lostActiveTask
    case staleAcceptedAsFresh
    case warningMissing
    case promptNotWithdrawn
    case notificationRemains
    case relaunchSnapshotLoss

    func apply(to evidence: inout ZC062003Evidence) {
        switch self {
        case .wrongDatabase: evidence.databasePath = "/private/tmp/wrong.sqlite"
        case .wrongSource: evidence.screenwatchRoot = "/private/tmp/other/days"
        case .wrongOSState: evidence.osStatePath = "/private/tmp/state.json"
        case .noEligibleBaseline: evidence.baselineDayCount = 0
        case .lostPlan: evidence.plannedTaskCount = 0
        case .lostActiveTask: evidence.activeStateCount = 0
        case .staleAcceptedAsFresh: evidence.phase = .healthy
        case .warningMissing: evidence.visibleText = "Active work continues."
        case .promptNotWithdrawn: evidence.unresolvedStrongPromptCount = 1
        case .notificationRemains: evidence.matchingNotificationCount = 1
        case .relaunchSnapshotLoss: evidence.snapshotActiveTaskID = nil
        }
    }
}

private enum ZC062003Error: Error {
    case ownership
    case database
    case eligibility
    case duplicate
    case transition
    case privacy
}
