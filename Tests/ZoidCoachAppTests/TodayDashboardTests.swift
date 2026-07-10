import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func urgencyUsesDeadlineBeforeReminderPriority() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

    #expect(TaskUrgency.resolve(dueDate: now, priority: .none, referenceDate: now, calendar: calendar) == .high)
    #expect(TaskUrgency.resolve(dueDate: tomorrow, priority: .high, referenceDate: now, calendar: calendar) == .high)
    #expect(TaskUrgency.resolve(dueDate: nil, priority: .low, referenceDate: now, calendar: calendar) == .low)
}

@Test
func recommendationIsStableAndSkipsBlockedTasks() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: now)
    let tasks = [
        TodayTaskRow(taskID: "z", title: "Z", estimateMinutes: 15, dueDate: nil, urgency: .high, state: .ready),
        TodayTaskRow(taskID: "a", title: "A", estimateMinutes: 15, dueDate: nil, urgency: .high, state: .ready),
        TodayTaskRow(taskID: "blocked", title: "Blocked", estimateMinutes: 5, dueDate: now, urgency: .high, state: .blocked)
    ]

    let recommendation = NextTaskRecommender().recommend(tasks: tasks, referenceDate: now, availableMinutes: 30, coverage: coverage)

    #expect(recommendation.taskID == "a")
}

@Test
func staleTelemetryReportsLimitedCoverageWithoutFakeTotals() {
    let now = Date(timeIntervalSince1970: 1_700_001_200)
    let observation = BehaviorObservation(observedAt: Date(timeIntervalSince1970: 1_700_000_000), application: "Safari", classification: .work)

    let result = BehaviorSessionizer().summarize(observations: [observation], now: now)

    #expect(result.coverage.isLimited)
    #expect(result.summary.workMinutes == 0)
}

@Test
func gamingStatusAppliesPriorityRewardOnlyWhenRecorded() {
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    let calculator = GamingStatusCalculator()

    #expect(calculator.status(policy: GamingPolicy(), gamingMinutes: 20, rewardApplied: false, coverage: coverage).unlockedRemainingMinutes == 40)
    #expect(calculator.status(policy: GamingPolicy(), gamingMinutes: 20, rewardApplied: true, coverage: coverage).unlockedRemainingMinutes == 55)
}

@Test
func replayClassifiesEachBehaviorBucketWithoutTreatingGapsAsTime() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let observations = [
        BehaviorObservation(observedAt: start, application: "Xcode", classification: .work),
        BehaviorObservation(observedAt: start.addingTimeInterval(60), application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(120), application: "YouTube", classification: .distracting),
        BehaviorObservation(observedAt: start.addingTimeInterval(180), application: "ScreenSaver", classification: .idle),
        BehaviorObservation(observedAt: start.addingTimeInterval(240), application: nil, classification: .unknown),
        BehaviorObservation(observedAt: start.addingTimeInterval(300), application: "Xcode", classification: .work),
        BehaviorObservation(observedAt: start.addingTimeInterval(900), application: "Xcode", classification: .work)
    ]

    let result = BehaviorSessionizer().summarize(observations: observations, now: start.addingTimeInterval(900), staleAfter: 1_000)

    #expect(result.summary.workMinutes == 1)
    #expect(result.summary.gamingOrDistractingMinutes == 2)
    #expect(result.summary.gamingMinutes == 1)
    #expect(result.summary.distractingMinutes == 1)
    #expect(result.summary.idleMinutes == 1)
    #expect(result.summary.unknownMinutes == 1)
}

@Test
func gamingAllowanceUsesOnlyClassifiedGamingTime() {
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    let summary = BehaviorSummary(workMinutes: 10, gamingMinutes: 12, distractingMinutes: 25, idleMinutes: 0, unknownMinutes: 0)

    let status = GamingStatusCalculator().status(policy: GamingPolicy(), gamingMinutes: summary.gamingMinutes, rewardApplied: false, coverage: coverage)

    #expect(summary.gamingOrDistractingMinutes == 37)
    #expect(status.usedMinutes == 12)
    #expect(status.unlockedRemainingMinutes == 48)
}
