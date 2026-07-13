import Foundation
import Testing
@testable import ZoidCoachApp

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
