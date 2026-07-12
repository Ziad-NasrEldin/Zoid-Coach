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

@Test
func pauseReasonPersistsAcrossRestartAndClosesWhenWorkResumes() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-pause-reason-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    do {
        let store = try TaskExecutionStore(databaseURL: url)
        try store.apply(.start, taskID: "task", at: start)
        try store.apply(.pauseForBreak, taskID: "task", at: start.addingTimeInterval(300))
        let paused = try store.snapshot(for: ["task"], now: start.addingTimeInterval(600))["task"]
        #expect(paused?.state == .paused)
        #expect(paused?.latestPauseReason == .break)
        #expect(paused?.elapsedMinutes == 5)
    }

    let restarted = try TaskExecutionStore(databaseURL: url)
    let restored = try restarted.snapshot(for: ["task"], now: start.addingTimeInterval(900))["task"]
    #expect(restored?.state == .paused)
    #expect(restored?.latestPauseReason == .break)
    #expect(restored?.elapsedMinutes == 5)

    try restarted.apply(.resume, taskID: "task", at: start.addingTimeInterval(900))
    let resumed = try restarted.snapshot(for: ["task"], now: start.addingTimeInterval(1_020))["task"]
    #expect(resumed?.state == .active)
    #expect(resumed?.latestPauseReason == .break)
    #expect(resumed?.elapsedMinutes == 7)
}

@Test
func switchingTasksRecordsReasonAndPreservesEarlierElapsedTime() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-switch-reason-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.start, taskID: "first", at: start)
    try store.apply(.start, taskID: "second", at: start.addingTimeInterval(240))
    let state = try store.snapshot(for: ["first", "second"], now: start.addingTimeInterval(360))

    #expect(state["first"]?.state == .paused)
    #expect(state["first"]?.latestPauseReason == .switchingTasks)
    #expect(state["first"]?.elapsedMinutes == 4)
    #expect(state["second"]?.state == .active)
    #expect(state["second"]?.elapsedMinutes == 2)
}

@Test
func completingPausedTaskRetainsTimeAndEndsItsPauseEpisode() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-complete-paused-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.start, taskID: "task", at: start)
    try store.apply(.pauseDoneForNow, taskID: "task", at: start.addingTimeInterval(180))
    try store.apply(.complete, taskID: "task", at: start.addingTimeInterval(600))
    let completed = try store.snapshot(for: ["task"], now: start.addingTimeInterval(1_200))["task"]

    #expect(completed?.state == .completed)
    #expect(completed?.latestPauseReason == .doneForNow)
    #expect(completed?.elapsedMinutes == 3)
}
