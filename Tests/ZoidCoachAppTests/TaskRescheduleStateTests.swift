import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func rescheduleDefaultsToTomorrowInTheCurrentCalendar() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 23, minute: 45)))
    let state = TaskRescheduleState(referenceDate: now, calendar: calendar)

    #expect(calendar.component(.day, from: state.selectedDate) == 14)
    #expect(calendar.component(.hour, from: state.selectedDate) == 0)
}

@Test
func promptRescheduleRequestRequiresAnExplicitActionAndTaskIdentity() throws {
    let valid = PromptEpisode(
        id: "prompt",
        decisionKey: "gaming:1",
        type: "GAMING_DRIFT",
        state: .presented,
        title: "Check the plan",
        summary: "A task may need a different day.",
        actions: [PromptAction(kind: .rescheduleTask, title: "Reschedule")],
        payload: ["taskID": "task-1", "taskTitle": "Prepare migration plan"],
        createdAt: Date()
    )
    let missingTask = PromptEpisode(
        id: "missing-task",
        decisionKey: "gaming:2",
        type: "GAMING_DRIFT",
        state: .presented,
        title: "Check the plan",
        summary: "A task may need a different day.",
        actions: [PromptAction(kind: .rescheduleTask, title: "Reschedule")],
        createdAt: Date()
    )
    let wrongAction = PromptEpisode(
        id: "wrong-action",
        decisionKey: "gaming:3",
        type: "GAMING_DRIFT",
        state: .presented,
        title: "Check the plan",
        summary: "A task may need a different day.",
        actions: [PromptAction(kind: .pauseTask, title: "Pause")],
        payload: ["taskID": "task-1"],
        createdAt: Date()
    )

    let request = try #require(PromptTaskRescheduleRequest(episode: valid))
    #expect(request.taskID == "task-1")
    #expect(request.taskTitle == "Prepare migration plan")
    #expect(PromptTaskRescheduleRequest(episode: missingTask) == nil)
    #expect(PromptTaskRescheduleRequest(episode: wrongAction) == nil)
}

@Test
func rescheduleRejectsTodayAndNormalizesAFutureSelectionToLocalMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 10)))
    let state = TaskRescheduleState(referenceDate: now, calendar: calendar)
    #expect(state.validated(now, calendar: calendar) == .failure(.mustBeFuture))

    let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 15)))
    let validated = try #require(try? state.validated(later, calendar: calendar).get())
    #expect(calendar.component(.day, from: validated) == 16)
    #expect(calendar.component(.hour, from: validated) == 0)
}
