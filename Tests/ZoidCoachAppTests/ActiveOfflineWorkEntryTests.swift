import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@MainActor
@Test
func activeOfflineWorkEntryPersistsOnceAndRemainsSeparateFromScreenwatch() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-active-offline-work-\(UUID().uuidString).sqlite")
    defer { removeActiveOfflineWorkDatabase(databaseURL) }
    let store = try DailyReviewStore(databaseURL: databaseURL, timeZone: TimeZone(secondsFromGMT: 0)!)
    let fixedNow = Date(timeIntervalSince1970: 1_783_699_200)
    let startedAt = fixedNow.addingTimeInterval(-45 * 60)
    let controller = ActiveOfflineWorkEntryController(
        taskID: "task-research",
        taskTitle: "Research migration risks",
        startedAt: startedAt,
        calendar: utcActiveOfflineWorkCalendar,
        now: { fixedNow }
    ) { sourceDay, taskID, startedAt, durationMinutes, note in
        _ = try store.saveOfflineWork(
            id: nil,
            sourceDay: sourceDay,
            taskID: taskID,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            note: note
        )
    }
    controller.durationMinutes = 35
    controller.note = "  Read the deployment notes  "

    #expect(controller.save())
    #expect(!controller.save())

    let snapshot = try store.load(sourceDay: "2026-07-10")
    let entry = try #require(snapshot.offlineWork.first)
    #expect(snapshot.offlineWork.count == 1)
    #expect(entry.taskID == "task-research")
    #expect(entry.durationMinutes == 35)
    #expect(entry.note == "Read the deployment notes")
    #expect(snapshot.offlineMinutes == 35)
    #expect(snapshot.actualMinutes == 35)
    #expect(snapshot.observedMinutes == 0)
    #expect(controller.successMessage?.contains("separate from Screenwatch evidence") == true)
}

@MainActor
@Test
func activeOfflineWorkEntryRejectsFutureAndOutOfBoundsValuesWithoutWriting() {
    let fixedNow = Date(timeIntervalSince1970: 1_783_699_200)
    var saves = 0
    let controller = ActiveOfflineWorkEntryController(
        taskID: "task",
        taskTitle: "Task",
        startedAt: fixedNow.addingTimeInterval(60),
        calendar: utcActiveOfflineWorkCalendar,
        now: { fixedNow }
    ) { _, _, _, _, _ in saves += 1 }

    #expect(!controller.canSave)
    #expect(!controller.save())
    #expect(controller.errorMessage == "Start time cannot be in the future.")
    #expect(saves == 0)

    controller.startedAt = fixedNow
    controller.durationMinutes = 4
    #expect(!controller.canSave)
    #expect(!controller.save())
    #expect(controller.errorMessage?.contains("between 5 minutes and 4 hours") == true)
    #expect(saves == 0)
}

private var utcActiveOfflineWorkCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func removeActiveOfflineWorkDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
