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

@Test
func boundedSprintCountsDownWithoutResettingOnDuplicateStart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-idempotent-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.startSprint10, taskID: "task", at: start)
    try store.apply(.startSprint10, taskID: "task", at: start.addingTimeInterval(60))

    let sprint = try #require(try store.activeTask(now: start.addingTimeInterval(180))?.sprint)
    #expect(sprint.durationMinutes == 10)
    #expect(sprint.elapsedSeconds == 180)
    #expect(sprint.remainingSeconds == 420)
    #expect(sprint.state == .active)
}

@Test
func customSprintAcceptsBoundedDurationAndRejectsMalformedBounds() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-custom-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    #expect(throws: TaskExecutionStoreError.self) {
        try store.startSprint(taskID: "task", durationMinutes: 0, at: start)
    }
    #expect(throws: TaskExecutionStoreError.self) {
        try store.startSprint(taskID: "task", durationMinutes: 241, at: start)
    }

    try store.startSprint(taskID: "task", durationMinutes: 37, at: start)
    let sprint = try #require(try store.activeTask(now: start.addingTimeInterval(120))?.sprint)
    #expect(sprint.durationMinutes == 37)
    #expect(sprint.remainingSeconds == 2_100)
}

@Test
func pausedSprintSurvivesRestartAndResumesFromPreservedRemainingTime() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-restart-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    do {
        let store = try TaskExecutionStore(databaseURL: url)
        try store.apply(.startSprint10, taskID: "task", at: start)
        try store.apply(.pauseForBreak, taskID: "task", at: start.addingTimeInterval(120))
    }

    let restored = try TaskExecutionStore(databaseURL: url)
    let paused = try #require(try restored.sprintSnapshot(taskID: "task", now: start.addingTimeInterval(3_600)))
    #expect(paused.state == .paused)
    #expect(paused.remainingSeconds == 480)

    try restored.apply(.resume, taskID: "task", at: start.addingTimeInterval(3_600))
    let resumed = try #require(try restored.activeTask(now: start.addingTimeInterval(3_660))?.sprint)
    #expect(resumed.state == .active)
    #expect(resumed.remainingSeconds == 420)
}

@Test
func sleepingPastSprintEndNeverCompletesTaskAndCanContinueOpenEnded() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-sleep-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.startSprint20, taskID: "task", at: start)
    let afterWake = try #require(try store.activeTask(now: start.addingTimeInterval(1_500)))
    #expect(afterWake.taskID == "task")
    #expect(afterWake.sprint?.state == .expired)
    #expect(afterWake.sprint?.remainingSeconds == 0)

    try store.apply(.continueOpenEnded, taskID: "task", at: start.addingTimeInterval(1_500))
    let continued = try #require(try store.activeTask(now: start.addingTimeInterval(1_800)))
    #expect(continued.taskID == "task")
    #expect(continued.sprint?.state == .continuedOpenEnded)
}

@Test
func switchingTasksPausesBoundedSprintAndPreservesItsTime() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-switch-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.startSprint25, taskID: "first", at: start)
    try store.apply(.start, taskID: "second", at: start.addingTimeInterval(180))

    let first = try #require(try store.sprintSnapshot(taskID: "first", now: start.addingTimeInterval(600)))
    #expect(first.state == .paused)
    #expect(first.remainingSeconds == 1_320)
    #expect(try store.activeTask(now: start.addingTimeInterval(600))?.taskID == "second")
}

@Test
func completingTaskFinishesItsBoundedSprint() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-sprint-complete-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try TaskExecutionStore(databaseURL: url)

    try store.apply(.startSprint10, taskID: "task", at: start)
    try store.apply(.complete, taskID: "task", at: start.addingTimeInterval(90))

    #expect(try store.activeTask(now: start.addingTimeInterval(120)) == nil)
    #expect(try store.sprintSnapshot(taskID: "task", now: start.addingTimeInterval(120)) == nil)
    #expect(try store.snapshot(for: ["task"], now: start.addingTimeInterval(120))["task"]?.state == .completed)
}
