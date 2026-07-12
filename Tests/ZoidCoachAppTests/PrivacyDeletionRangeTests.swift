import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func inclusivePrivacyDeletionRangeIncludesTheWholeThroughDayAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let formatter = ISO8601DateFormatter()
    let start = try #require(formatter.date(from: "2026-03-07T17:00:00Z"))
    let through = try #require(formatter.date(from: "2026-03-08T17:00:00Z"))

    let range = try #require(PrivacyDeletionRange.inclusive(from: start, through: through, calendar: calendar))

    #expect(calendar.component(.hour, from: range.start) == 0)
    #expect(calendar.component(.hour, from: range.through) == 0)
    #expect(calendar.dateComponents([.day], from: range.through, to: range.exclusiveEnd).day == 1)
    #expect(range.exclusiveEnd.timeIntervalSince(range.through) == 23 * 60 * 60)
}

@Test
func inclusivePrivacyDeletionRangeRejectsReversedDates() throws {
    let formatter = ISO8601DateFormatter()
    let later = try #require(formatter.date(from: "2026-07-12T12:00:00Z"))
    let earlier = try #require(formatter.date(from: "2026-07-10T12:00:00Z"))

    #expect(PrivacyDeletionRange.inclusive(from: later, through: earlier) == nil)
}
