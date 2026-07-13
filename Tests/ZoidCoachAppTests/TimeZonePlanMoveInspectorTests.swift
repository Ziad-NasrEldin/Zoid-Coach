import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func timeZonePlanMoveInspectorFindsTheDurableSourceDayPlan() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("time-zone-plan-move-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:30:00Z"))
    let planStore = try AutonomousPlanStore(
        databaseURL: databaseURL,
        timeZoneIdentifier: { "UTC" }
    )
    try planStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "first", title: "First", rank: 1, estimateMinutes: 30, reason: "due", score: 2),
                PlannedTask(taskID: "second", title: "Second", rank: 2, estimateMinutes: 20, reason: "due", score: 1),
            ],
            mainObjectiveTaskID: "first",
            plannedFocusMinutes: 50,
            availableFocusMinutes: 90
        ),
        for: instant
    )

    let inspected = try TimeZonePlanMoveInspector(databaseURL: databaseURL).warning(
        from: "UTC",
        to: "America/Los_Angeles",
        at: instant
    )
    let warning = try #require(inspected)

    #expect(warning.sourceDayKey == "2026-07-14")
    #expect(warning.destinationDayKey == "2026-07-13")
    #expect(warning.taskCount == 2)
    #expect(warning.confirmationMessage.contains("2 planned tasks"))
    #expect(warning.confirmationMessage.contains("America/Los_Angeles"))
}

@Test
func timeZonePlanMoveInspectorSkipsSameDayAndEmptyPlanChanges() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("time-zone-plan-no-warning-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    _ = try PolicyStore(databaseURL: databaseURL).save(.defaults(timeZoneIdentifier: "UTC"))
    let inspector = TimeZonePlanMoveInspector(databaseURL: databaseURL)
    let midday = try #require(ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z"))
    let boundary = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:30:00Z"))

    #expect(try inspector.warning(from: "UTC", to: "Europe/London", at: midday) == nil)
    #expect(try inspector.warning(from: "UTC", to: "America/Los_Angeles", at: boundary) == nil)
}

@Test
func timeZonePlanMoveInspectorHandlesDSTBoundaryWithoutOverprompting() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("time-zone-plan-dst-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let beforeDSTJump = try #require(ISO8601DateFormatter().date(from: "2026-03-08T04:30:00Z"))
    let afterDSTJump = try #require(ISO8601DateFormatter().date(from: "2026-03-08T07:30:00Z"))
    let planStore = try AutonomousPlanStore(databaseURL: databaseURL, timeZoneIdentifier: { "UTC" })
    try planStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "dst", title: "DST boundary", rank: 1, estimateMinutes: 30, reason: "due", score: 1)],
            mainObjectiveTaskID: "dst",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: beforeDSTJump
    )
    let inspector = TimeZonePlanMoveInspector(databaseURL: databaseURL)

    let crossing = try #require(try inspector.warning(
        from: "UTC",
        to: "America/New_York",
        at: beforeDSTJump
    ))
    #expect(crossing.sourceDayKey == "2026-03-08")
    #expect(crossing.destinationDayKey == "2026-03-07")
    #expect(crossing.confirmationMessage == "1 planned task currently belongs to 2026-03-08 in UTC. In America/New_York, this instant is 2026-03-07. Saving changes which local plan day Zoid 666 treats as current.")

    #expect(try inspector.warning(
        from: "UTC",
        to: "America/New_York",
        at: afterDSTJump
    ) == nil)
}
