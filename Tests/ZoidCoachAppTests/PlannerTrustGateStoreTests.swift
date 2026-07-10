import Foundation
import Testing
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
}
