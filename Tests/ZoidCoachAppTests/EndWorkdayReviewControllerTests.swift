import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func endWorkdayReviewControllerSendsTheDurableEndDayCommandOnce() async {
    let recorder = EndWorkdayCommandRecorder()
    let controller = EndWorkdayReviewController { command, taskID in
        await recorder.record(command: command, taskID: taskID)
    }

    let succeeded = await controller.endWorkday(taskID: "priority-1")

    #expect(succeeded)
    #expect(await recorder.commands == [.init(command: .pauseForEndOfDay, taskID: "priority-1")])
    #expect(controller.statusMessage == "Workday ended. Opening today's review.")
    #expect(!controller.isEndingWorkday)
}

@MainActor
@Test
func endWorkdayReviewControllerKeepsTheUserInPlaceAfterFailure() async {
    let controller = EndWorkdayReviewController { _, _ in
        throw EndWorkdayReviewTestError.unavailable
    }

    let succeeded = await controller.endWorkday(taskID: "priority-1")

    #expect(!succeeded)
    #expect(controller.statusMessage?.contains("active task is unchanged") == true)
    #expect(controller.statusMessage?.contains("try again") == true)
    #expect(!controller.isEndingWorkday)
}

@MainActor
@Test
func endWorkdayReviewControllerRejectsADuplicateWhileTheFirstCommandIsRunning() async {
    let recorder = EndWorkdayCommandRecorder()
    let controller = EndWorkdayReviewController { command, taskID in
        await recorder.record(command: command, taskID: taskID)
        try await Task.sleep(for: .milliseconds(100))
    }
    let first = Task { @MainActor in
        await controller.endWorkday(taskID: "priority-1")
    }
    while !controller.isEndingWorkday {
        await Task.yield()
    }

    let duplicateSucceeded = await controller.endWorkday(taskID: "priority-1")
    let firstSucceeded = await first.value

    #expect(firstSucceeded)
    #expect(!duplicateSucceeded)
    #expect(await recorder.commands.count == 1)
}

@MainActor
@Test
func endWorkdayReviewControllerPersistsTheEndingWorkdayStateAcrossRestart() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("end-workday-review-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let startedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-13T08:00:00Z"))
    let endedAt = startedAt.addingTimeInterval(90 * 60)
    let store = try TaskExecutionStore(databaseURL: databaseURL)
    try store.apply(.start, taskID: "priority-1", at: startedAt)
    let controller = EndWorkdayReviewController { command, taskID in
        try store.apply(command, taskID: taskID, at: endedAt)
    }

    #expect(await controller.endWorkday(taskID: "priority-1"))

    let reopened = try TaskExecutionStore(databaseURL: databaseURL)
    let restored = try #require(try reopened.snapshot(for: ["priority-1"], now: endedAt)["priority-1"])
    #expect(restored.state == .paused)
    #expect(restored.latestPauseReason == .endingWorkday)
    #expect(restored.elapsedMinutes == 90)
    #expect(try reopened.activeTask(now: endedAt) == nil)
}

private actor EndWorkdayCommandRecorder {
    struct Command: Equatable {
        let command: TaskActivityCommand
        let taskID: String
    }

    private(set) var commands: [Command] = []

    func record(command: TaskActivityCommand, taskID: String) {
        commands.append(Command(command: command, taskID: taskID))
    }
}

private enum EndWorkdayReviewTestError: Error {
    case unavailable
}
