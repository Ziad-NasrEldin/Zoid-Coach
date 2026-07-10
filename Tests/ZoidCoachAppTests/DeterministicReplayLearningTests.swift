import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func replayIsDeterministicAndExercisesEverySimulatedSourceWithoutLiveAccess() {
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let start = Date(timeIntervalSince1970: 1_783_294_200)
    let clock = FixedReplayClock(now: start)
    let identifiers = SequenceIdentifierGenerator(prefix: "fixture")
    let fixture = SimulatedDayFixture(clock: clock, identifiers: identifiers, timeZone: timeZone)
    let events = [
        fixture.event(at: start.addingTimeInterval(60), kind: .reminder(.upserted(id: "r1", title: "Write plan", estimateMinutes: 45))),
        fixture.event(at: start.addingTimeInterval(120), kind: .calendar(.reserved(id: "c1", start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(5_400)))),
        fixture.event(at: start.addingTimeInterval(180), kind: .behavior(.observed(application: "Xcode", classification: .work))),
        fixture.event(at: start.addingTimeInterval(240), kind: .sleep),
        fixture.event(at: start.addingTimeInterval(300), kind: .wake),
        fixture.event(at: start.addingTimeInterval(360), kind: .prompt(.presented(id: "p1", topic: "Start focused work"))),
        fixture.event(at: start.addingTimeInterval(420), kind: .action(.recorded(id: "a1", name: "start_task", succeeded: true)))
    ]

    let forward = DeterministicDayReplay.replay(events)
    let reversed = DeterministicDayReplay.replay(events.reversed())

    #expect(forward == reversed)
    #expect(forward.reminders["r1"]?.title == "Write plan")
    #expect(forward.calendarReservations.count == 1)
    #expect(forward.behaviorObservations.count == 1)
    #expect(forward.isSleeping == false)
    #expect(forward.prompts["p1"]?.topic == "Start focused work")
    #expect(forward.actions["a1"]?.succeeded == true)
    #expect(forward.processedEventIDs.count == 7)
}

@Test
func missedNightlyRunUsesLocalDSTSemanticsAndExecutesOnlyOnceAfterWake() {
    let timeZone = TimeZone(identifier: "America/New_York")!
    let calendar = replayCalendar(timeZone: timeZone)
    let sleep = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 55))!
    let wake = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 15))!
    let fixture = SimulatedDayFixture(
        clock: FixedReplayClock(now: sleep),
        identifiers: SequenceIdentifierGenerator(prefix: "dst"),
        timeZone: timeZone
    )
    let policy = NightlyReplayPolicy(
        version: 4,
        timeZoneIdentifier: timeZone.identifier,
        planningTime: LocalTime(hour: 2, minute: 30)
    )
    let events = [
        fixture.event(at: sleep, kind: .sleep),
        fixture.event(at: wake, kind: .wake),
        fixture.event(at: wake.addingTimeInterval(1), kind: .wake)
    ]

    let once = DeterministicDayReplay.replay(events, nightlyPolicy: policy)
    let replayed = DeterministicDayReplay.replay(events, initialState: once, nightlyPolicy: policy)

    #expect(once.nightlyPlanningRuns == [
        NightlyPlanningRun(targetLocalDay: "2026-03-09", executedAt: wake, delayedAfterWake: true, policyVersion: 4)
    ])
    #expect(replayed.nightlyPlanningRuns == once.nightlyPlanningRuns)
}

private func replayCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

@Test
func estimateLearningUsesRecentRobustMedianAndKeepsRollbackDataWithinBounds() {
    let now = Date(timeIntervalSince1970: 1_783_294_200)
    let context = EstimateLearningContext(taskType: "writing", project: "Zoid")
    let actualMinutes = [30, 33, 36, 39, 3_600]
    let samples = actualMinutes.enumerated().map { index, actual in
        EstimateLearningSample(
            id: "sample-\(index)",
            context: context,
            estimatedMinutes: 30,
            actualAlignedMinutes: actual,
            trackingCoverage: 0.95,
            completedAt: now.addingTimeInterval(TimeInterval(index))
        )
    }
    let policy = EstimateLearningPolicy(
        version: 7,
        minimumSamples: 4,
        rollingSampleLimit: 8,
        minimumTrackingCoverage: 0.8,
        minimumRatio: 0.5,
        maximumRatio: 2,
        minimumRecommendedMinutes: 15,
        maximumRecommendedMinutes: 100
    )

    let proposal = EstimateLearner(clock: FixedReplayClock(now: now)).proposal(
        for: context,
        currentEstimateMinutes: 90,
        samples: samples,
        policy: policy
    )

    #expect(proposal?.sampleCount == 5)
    #expect(proposal?.rawMedianRatio == 1.2)
    #expect(proposal?.recommendedEstimateMinutes == 100)
    #expect(proposal?.rollbackEstimateMinutes == 90)
    #expect(proposal?.policyVersion == 7)
    #expect(proposal?.evidenceIDs == ["sample-4", "sample-3", "sample-2", "sample-1", "sample-0"])

    let extremeSamples = actualMinutes.enumerated().map { index, actual in
        EstimateLearningSample(
            id: "extreme-\(index)",
            context: context,
            estimatedMinutes: 30,
            actualAlignedMinutes: actual * 10,
            trackingCoverage: 1,
            completedAt: now.addingTimeInterval(TimeInterval(index))
        )
    }
    let bounded = EstimateLearner(clock: FixedReplayClock(now: now)).proposal(
        for: context,
        currentEstimateMinutes: 90,
        samples: extremeSamples,
        policy: policy
    )
    #expect(bounded?.appliedRatio == 2)
    #expect(bounded?.recommendedEstimateMinutes == 100)

    let sparse = EstimateLearner(clock: FixedReplayClock(now: now)).proposal(
        for: context,
        currentEstimateMinutes: 90,
        samples: Array(samples.prefix(3)),
        policy: policy
    )
    #expect(sparse == nil)
}

@Test
func sparseWorkEvidenceDoesNotInventAPreferredWindow() {
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let calendar = replayCalendar(timeZone: timeZone)
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!
    let samples = (0..<4).map { index in
        WorkWindowLearningSample(
            id: "work-\(index)",
            startedAt: calendar.date(byAdding: .day, value: index, to: start)!,
            endedAt: calendar.date(byAdding: .minute, value: 90, to: calendar.date(byAdding: .day, value: index, to: start)!)!,
            trackingCoverage: 0.95
        )
    }

    let proposal = PreferredWorkWindowLearner(clock: FixedReplayClock(now: start)).proposal(
        samples: samples,
        timeZoneIdentifier: timeZone.identifier,
        policy: PreferredWorkWindowLearningPolicy(minimumSamples: 5)
    )

    #expect(proposal == nil)
}

@Test
func preferredWorkWindowUsesLocalMedianAndCarriesPolicyAndRollbackValues() {
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let calendar = replayCalendar(timeZone: timeZone)
    let base = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    let starts = [(9, 0), (9, 15), (9, 30), (12, 0), (9, 20)]
    let durations = [60, 90, 120, 600, 75]
    let samples = zip(starts, durations).enumerated().map { index, pair in
        let day = calendar.date(byAdding: .day, value: index, to: base)!
        let start = calendar.date(bySettingHour: pair.0.0, minute: pair.0.1, second: 0, of: day)!
        return WorkWindowLearningSample(
            id: "window-\(index)",
            startedAt: start,
            endedAt: calendar.date(byAdding: .minute, value: pair.1, to: start)!,
            trackingCoverage: 1
        )
    }
    let rollback = WeeklyWorkWindow(
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
        start: LocalTime(hour: 8, minute: 0),
        end: LocalTime(hour: 17, minute: 0)
    )
    let policy = PreferredWorkWindowLearningPolicy(version: 9, minimumSamples: 5, maximumLearnedDurationMinutes: 240)

    let proposal = PreferredWorkWindowLearner(clock: FixedReplayClock(now: base)).proposal(
        samples: samples,
        timeZoneIdentifier: timeZone.identifier,
        rollbackWindow: rollback,
        policy: policy
    )

    #expect(proposal?.preferredWindow.start == LocalTime(hour: 9, minute: 20))
    #expect(proposal?.preferredWindow.end == LocalTime(hour: 10, minute: 50))
    #expect(proposal?.preferredWindow.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
    #expect(proposal?.policyVersion == 9)
    #expect(proposal?.rollbackWindow == rollback)
}
