import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func plannerTrustGateRequiresSevenDistinctCapacitySafeShadowDays() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trust-gate-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    let store = try PlannerTrustGateStore(databaseURL: url)
    for day in 1...6 {
        let status = try store.recordShadowCycle(localDay: "2026-07-0\(day)", planVersion: day, itemCount: 4, stayedWithinCapacity: true)
        #expect(status.allowsAutomaticWrites == false)
    }
    _ = try store.recordShadowCycle(localDay: "2026-07-06", planVersion: 99, itemCount: 4, stayedWithinCapacity: true)
    #expect(try store.status().observedCycleCount == 6)
    let ready = try store.recordShadowCycle(localDay: "2026-07-07", planVersion: 7, itemCount: 4, stayedWithinCapacity: true)
    #expect(ready.allowsAutomaticWrites)
    #expect(ready.allowsWakeWrites == false)
    for day in 8...14 {
        _ = try store.recordShadowCycle(localDay: "2026-07-\(day)", planVersion: day, itemCount: 4, stayedWithinCapacity: true)
    }
    #expect(try store.status().allowsWakeWrites)
}

@Test
func plannerTrustGateDoesNotCountEmptyPlans() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trust-gate-empty-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    let store = try PlannerTrustGateStore(databaseURL: url)
    for day in 1...7 {
        _ = try store.recordShadowCycle(localDay: "2026-08-0\(day)", planVersion: day, itemCount: 0, stayedWithinCapacity: true)
    }
    #expect(try store.status().observedCycleCount == 0)
    #expect(try store.status().allowsAutomaticWrites == false)
}

@Test
func historicalShadowAuditReportsEvidenceGapsWithoutFabricatingTrustCycles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trust-gate-audit-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try PlannerTrustGateStore(databaseURL: url)
    let planStore = try AutonomousPlanStore(databaseURL: url, timeZoneIdentifier: { "UTC" })
    let day = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
    try planStore.replaceDailyPlan(DailyPlanProposal(
        items: [
            PlannedTask(taskID: "task-1", title: "One", rank: 1, estimateMinutes: 60, reason: "deadline", score: 10),
            PlannedTask(taskID: "task-2", title: "Two", rank: 2, estimateMinutes: 30, reason: "carryover", score: 5)
        ],
        mainObjectiveTaskID: "task-1", plannedFocusMinutes: 90, availableFocusMinutes: 120
    ), for: day)

    let report = try store.historicalShadowEvaluationReport()

    #expect(report.count == 1)
    #expect(report[0].localDay == "2026-07-08")
    #expect(report[0].evidenceCoverage == .insufficientForReplay)
    #expect(report[0].missingEvidence.contains(.historicalTaskSnapshot))
    #expect(report[0].missingEvidence.contains(.historicalCalendarSnapshot))
    #expect(try store.status().observedCycleCount == 0)
}

@Test
func onlyCompleteRetrospectiveComparisonsCanAdvanceTrustGate() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trust-gate-retrospective-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try PlannerTrustGateStore(databaseURL: url)
    let incomplete = RetrospectiveShadowEvaluation(
        localDay: "2026-07-08", planVersion: 1, itemCount: 3,
        stayedWithinCapacity: true, externalWritesSuppressed: true,
        comparedWithObservedOutcome: false, evidenceCoverage: .complete
    )
    let complete = RetrospectiveShadowEvaluation(
        localDay: "2026-07-09", planVersion: 2, itemCount: 3,
        stayedWithinCapacity: true, externalWritesSuppressed: true,
        comparedWithObservedOutcome: true, evidenceCoverage: .complete
    )

    #expect(try store.recordRetrospectiveEvaluation(incomplete) == false)
    #expect(try store.recordRetrospectiveEvaluation(complete) == true)
    #expect(try store.status().observedCycleCount == 1)
}
