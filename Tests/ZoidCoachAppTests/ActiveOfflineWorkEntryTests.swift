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
    ) { id, sourceDay, taskID, startedAt, durationMinutes, note in
        _ = try store.saveOfflineWork(
            id: id,
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
    #expect(controller.successMessage == "Recorded 35 minutes away from the Mac for Research migration risks. It will count as actual task time and remain separate from Screenwatch evidence.")
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
    ) { _, _, _, _, _, _ in saves += 1 }

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

@MainActor
@Test
func activeOfflineWorkDefaultsToACompletedIntervalAndRejectsFutureEnd() {
    let fixedNow = Date(timeIntervalSince1970: 1_783_699_200)
    var saves = 0
    let controller = ActiveOfflineWorkEntryController(
        taskID: "task",
        taskTitle: "Task",
        calendar: utcActiveOfflineWorkCalendar,
        now: { fixedNow }
    ) { _, _, _, _, _, _ in saves += 1 }

    #expect(controller.startedAt == fixedNow.addingTimeInterval(-15 * 60))
    #expect(controller.canSave)

    controller.durationMinutes = 20
    #expect(!controller.canSave)
    #expect(!controller.save())
    #expect(controller.errorMessage?.contains("duration extends into the future") == true)
    #expect(saves == 0)
}

@MainActor
@Test
func identicalActiveOfflineWorkIsIdempotentAcrossReopenedSheets() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-active-offline-work-dedupe-\(UUID().uuidString).sqlite")
    defer { removeActiveOfflineWorkDatabase(databaseURL) }
    let store = try DailyReviewStore(databaseURL: databaseURL, timeZone: TimeZone(secondsFromGMT: 0)!)
    let fixedNow = Date(timeIntervalSince1970: 1_783_699_200)
    let startedAt = fixedNow.addingTimeInterval(-35 * 60)

    func controller(note: String) -> ActiveOfflineWorkEntryController {
        let controller = ActiveOfflineWorkEntryController(
            taskID: "task-research",
            taskTitle: "Research migration risks",
            startedAt: startedAt,
            calendar: utcActiveOfflineWorkCalendar,
            now: { fixedNow }
        ) { id, sourceDay, taskID, startedAt, durationMinutes, note in
            _ = try store.saveOfflineWork(
                id: id,
                sourceDay: sourceDay,
                taskID: taskID,
                startedAt: startedAt,
                durationMinutes: durationMinutes,
                note: note
            )
        }
        controller.durationMinutes = 35
        controller.note = note
        return controller
    }

    #expect(controller(note: "First note").save())
    #expect(controller(note: "Corrected note").save())

    let snapshot = try store.load(sourceDay: "2026-07-10")
    #expect(snapshot.offlineWork.count == 1)
    #expect(snapshot.offlineWork[0].note == "Corrected note")
    #expect(snapshot.offlineMinutes == 35)
}

@Test
func offlineWorkTaskTitleResolverShowsThePlannedTaskTitleAndKeepsAnHonestFallback() {
    let resolver = OfflineWorkTaskTitleResolver(titles: [
        "local:user:task-1": "Research migration risks"
    ])

    #expect(resolver.title(for: "local:user:task-1") == "Research migration risks")
    #expect(resolver.title(for: "external-task") == "external-task")
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
