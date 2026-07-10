import Foundation
import Testing
@testable import ZoidCoachInfrastructure

@Test
func startingAnotherTaskAtomicallyPausesTheExistingTask() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-execution-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try TaskExecutionStore(databaseURL: url)
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    try store.apply(.start, taskID: "first", at: start)
    try store.apply(.start, taskID: "second", at: start.addingTimeInterval(120))
    let state = try store.snapshot(for: ["first", "second"], now: start.addingTimeInterval(180))

    #expect(state["first"]?.state == .paused)
    #expect(state["second"]?.state == .active)
    #expect(state["first"]?.elapsedMinutes == 2)
}

@Test
func pausedTaskRestoresElapsedTimeWithoutDoubleCounting() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-execution-relaunch-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    do {
        let store = try TaskExecutionStore(databaseURL: url)
        try store.apply(.start, taskID: "task", at: start)
        try store.apply(.pause, taskID: "task", at: start.addingTimeInterval(180))
    }
    let restored = try TaskExecutionStore(databaseURL: url)
    let state = try restored.snapshot(for: ["task"], now: start.addingTimeInterval(600))

    #expect(state["task"]?.state == .paused)
    #expect(state["task"]?.elapsedMinutes == 3)
}
