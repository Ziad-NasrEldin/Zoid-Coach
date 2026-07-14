import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import ZoidCoachCore
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@Test
func weeklyPatternPresentationSeparatesHypothesisEvidenceAndAlternative() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 4,
        examples: [
            "Monday: 42 focused minutes",
            "Wednesday: 38 focused minutes",
        ],
        confidencePercent: 72
    ))

    #expect(presentation.hypothesis == "Focused work was more consistent before noon.")
    #expect(presentation.confidenceLabel == "72% CONFIDENCE")
    #expect(presentation.sampleLabel == "4 OBSERVED SAMPLES")
    #expect(presentation.evidenceHeading == "OBSERVED EVIDENCE")
    #expect(presentation.evidenceLines.count == 2)
    #expect(presentation.alternativeExplanation == "Meeting load may have been lighter on those mornings.")
    #expect(presentation.causalityCaveat.contains("do not prove why"))
    #expect(presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternPresentationDoesNotPresentZeroSamplesAsCausal() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 0,
        examples: ["A leftover example must not make zero samples sufficient."],
        confidencePercent: 88
    ))

    #expect(presentation.confidenceLabel == "INSUFFICIENT EVIDENCE")
    #expect(presentation.sampleLabel == "0 OBSERVED SAMPLES")
    #expect(presentation.evidenceHeading == "INSUFFICIENT EVIDENCE")
    #expect(presentation.evidenceLines == ["No observed examples support this hypothesis yet."])
    #expect(presentation.causalityCaveat.contains("Keep this as a question"))
    #expect(!presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternPresentationDoesNotTreatMissingExamplesAsEvidence() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 3,
        examples: ["  ", ""],
        confidencePercent: 64
    ))

    #expect(presentation.confidenceLabel == "INSUFFICIENT EVIDENCE")
    #expect(presentation.evidenceHeading == "INSUFFICIENT EVIDENCE")
    #expect(!presentation.hasSufficientEvidence)
}

@Test
func weeklyPatternExpandedAccessibilitySummaryNamesEveryEvidenceBoundary() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 1,
        examples: ["Tuesday: 31 focused minutes"],
        confidencePercent: 55
    ))

    let summary = presentation.accessibilitySummary(showsEvidence: true)
    #expect(summary.contains("Hypothesis:"))
    #expect(summary.contains("Observed evidence:"))
    #expect(summary.contains("Tuesday: 31 focused minutes"))
    #expect(summary.contains("Alternative explanation:"))
    #expect(summary.contains("NOT PROVEN CAUSE"))
}

@Test
func weeklyPatternCollapsedAccessibilitySummaryExcludesHiddenEvidenceAndAlternative() {
    let presentation = WeeklyReviewPatternPresentation(pattern: pattern(
        sampleCount: 2,
        examples: ["Private task title: 31 focused minutes"],
        confidencePercent: 55
    ))

    let summary = presentation.accessibilitySummary(showsEvidence: false)
    #expect(summary.contains("Hypothesis:"))
    #expect(summary.contains("2 OBSERVED SAMPLES"))
    #expect(summary.contains("55% CONFIDENCE"))
    #expect(summary.contains("NOT PROVEN CAUSE"))
    #expect(!summary.contains("Private task title"))
    #expect(!summary.contains("Observed evidence:"))
    #expect(!summary.contains("Alternative explanation:"))
}

@Test @MainActor
func weeklyPatternCardWrapsLongCopyAtConstrainedWidth() {
    let longPattern = WeeklyReviewPattern(
        id: "long-pattern",
        kind: .bestWorkWindow,
        title: "A deliberately long weekly pattern title",
        conclusion: "Focused work appeared more consistent before noon across several observed days, while the available evidence still leaves room for a different explanation.",
        sampleCount: 4,
        dateRange: WeeklyReviewDateRange(startDay: "2026-07-06", endDay: "2026-07-12"),
        examples: ["Tuesday morning included a long privacy-safe summary that must wrap inside the review card."],
        confidencePercent: 72,
        alternativeExplanation: "Meeting load may have been lighter on those mornings, which could explain the apparent pattern without implying a cause."
    )
    let host = NSHostingView(rootView: WeeklyPatternCard(pattern: longPattern).frame(width: 260))

    host.layoutSubtreeIfNeeded()
    let size = host.fittingSize

    #expect(size.width <= 260)
    #expect(size.height > 100)
    withExtendedLifetime(host) {}
}

@Test
func weeklyPatternPresentationIsDerivedAgainFromPersistedWeeklyEvidence() throws {
    let databaseURL = weeklyPresentationDatabaseURL()
    defer { removeWeeklyPresentationDatabase(databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        try insertWeeklyPresentationCoveredDay(
            databaseURL,
            day: day,
            epoch: 1_751_328_000 + Int64(offset * 86_400)
        )
    }
    let now = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!

    let first = try #require(try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyPresentationCalendar,
        now: { now }
    ).load().patterns.first)
    let reopened = try #require(try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyPresentationCalendar,
        now: { now }
    ).load().patterns.first)

    #expect(WeeklyReviewPatternPresentation(pattern: reopened) == WeeklyReviewPatternPresentation(pattern: first))
}

private func pattern(
    sampleCount: Int,
    examples: [String],
    confidencePercent: Int
) -> WeeklyReviewPattern {
    WeeklyReviewPattern(
        id: "best-work-window",
        kind: .bestWorkWindow,
        title: "Morning focus",
        conclusion: "Focused work was more consistent before noon.",
        sampleCount: sampleCount,
        dateRange: WeeklyReviewDateRange(startDay: "2026-07-06", endDay: "2026-07-12"),
        examples: examples,
        confidencePercent: confidencePercent,
        alternativeExplanation: "Meeting load may have been lighter on those mornings."
    )
}

private var weeklyPresentationCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "Africa/Cairo")!
    calendar.firstWeekday = 2
    return calendar
}

private func weeklyPresentationDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-weekly-presentation-\(UUID().uuidString).sqlite")
}

private func removeWeeklyPresentationDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private func insertWeeklyPresentationCoveredDay(_ url: URL, day: String, epoch: Int64) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw WeeklyPresentationFixtureError.open
    }
    defer { sqlite3_close(database) }
    let sql = """
    INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc)
    VALUES ('\(day)', 'accepted', '\(day)T18:00:00Z', '\(day)T18:00:00Z');
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at, classification)
    VALUES ('\(day)', \(epoch), '09:00', 'Code', '', '', 0, '\(day)T09:00:00Z', 'work'),
           ('\(day)', \(epoch + 1800), '09:30', 'Game', '', '', 0, '\(day)T09:30:00Z', 'gaming'),
           ('\(day)', \(epoch + 3600), '10:00', 'Messages', '', '', 0, '\(day)T10:00:00Z', 'distracting');
    """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw WeeklyPresentationFixtureError.write
    }
}

private enum WeeklyPresentationFixtureError: Error {
    case open
    case write
}
