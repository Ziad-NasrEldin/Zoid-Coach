import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func activeTaskContextAssessmentUsesNeutralEvidenceStates() {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let assessor = ActiveTaskContextAssessor()

    let aligned = assessor.assess(
        observations: [BehaviorObservation(observedAt: now.addingTimeInterval(-20), application: "Xcode", classification: .work)],
        now: now
    )
    #expect(aligned.state == .aligned)
    #expect(aligned.explanation.contains("signal, not proof"))

    let mismatched = assessor.assess(
        observations: [BehaviorObservation(observedAt: now.addingTimeInterval(-20), application: "Game", classification: .gaming)],
        now: now
    )
    #expect(mismatched.state == .mismatched)
    #expect(!mismatched.explanation.localizedCaseInsensitiveContains("unproductive"))

    let unknown = assessor.assess(
        observations: [BehaviorObservation(observedAt: now.addingTimeInterval(-20), application: "Browser", classification: .unknown)],
        now: now
    )
    #expect(unknown.state == .uncertain)
    #expect(unknown.explanation.contains("will not guess"))
}

@Test
func activeTaskContextAssessmentRefusesMissingAndStaleEvidence() {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let assessor = ActiveTaskContextAssessor()

    let missing = assessor.assess(observations: [], now: now)
    #expect(missing.state == .uncertain)
    #expect(missing.lastObservedAt == nil)

    let staleDate = now.addingTimeInterval(-901)
    let stale = assessor.assess(
        observations: [BehaviorObservation(observedAt: staleDate, application: "Xcode", classification: .work)],
        now: now
    )
    #expect(stale.state == .uncertain)
    #expect(stale.lastObservedAt == staleDate)
    #expect(stale.explanation.contains("stale"))
}

@Test
func todayReminderEligibilityUsesTheConfiguredLocalDayBoundary() throws {
    var cairo = Calendar(identifier: .gregorian)
    cairo.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let reference = try #require(cairo.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 23, minute: 45)))
    let beforeMidnight = try #require(cairo.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 23, minute: 59)))
    let midnight = try #require(cairo.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 0)))

    #expect(TodayReminderEligibility.isVisible(dueDate: nil, referenceDate: reference, calendar: cairo))
    #expect(TodayReminderEligibility.isVisible(dueDate: beforeMidnight, referenceDate: reference, calendar: cairo))
    #expect(!TodayReminderEligibility.isVisible(dueDate: midnight, referenceDate: reference, calendar: cairo))
    #expect(TodayReminderEligibility.isVisible(dueDate: reference.addingTimeInterval(-86_400), referenceDate: reference, calendar: cairo))
}

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
    #expect(recommendation.suggestedSprintMinutes == nil)
}

@Test
func oversizedRecommendationOffersABoundedSprintThatFitsAvailableTime() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: now)
    let task = TodayTaskRow(
        taskID: "large",
        title: "Prepare migration plan",
        estimateMinutes: 90,
        dueDate: now,
        urgency: .high,
        state: .ready
    )

    let recommendation = NextTaskRecommender().recommend(
        tasks: [task],
        referenceDate: now,
        availableMinutes: 20,
        coverage: coverage
    )

    #expect(recommendation.taskID == "large")
    #expect(recommendation.suggestedSprintMinutes == 20)
    #expect(recommendation.reasons.contains(.boundedSprint))
    #expect(recommendation.sentence.contains("20-minute sprint"))
    #expect(recommendation.sentence.contains("task will stay incomplete"))
}

@Test
func boundedSprintRecommendationCapsLongWindowsAndAvoidsZeroTime() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: now)
    let task = TodayTaskRow(
        taskID: "large",
        title: "Prepare migration plan",
        estimateMinutes: 120,
        dueDate: nil,
        urgency: .high,
        state: .ready
    )
    let recommender = NextTaskRecommender()

    let longWindow = recommender.recommend(tasks: [task], referenceDate: now, availableMinutes: 40, coverage: coverage)
    let noWindow = recommender.recommend(tasks: [task], referenceDate: now, availableMinutes: 0, coverage: coverage)

    #expect(longWindow.suggestedSprintMinutes == 25)
    #expect(noWindow.suggestedSprintMinutes == nil)
    #expect(noWindow.reasons.contains(.boundedSprint) == false)
}

@Test
func recommendationSprintPresentationUsesLiveAvailability() {
    #expect(RecommendationSprintPresentation.durationMinutes(estimateMinutes: 90, availableMinutes: 20) == 20)
    #expect(RecommendationSprintPresentation.durationMinutes(estimateMinutes: 90, availableMinutes: 40) == 25)
    #expect(RecommendationSprintPresentation.durationMinutes(estimateMinutes: 90, availableMinutes: 0) == nil)
    #expect(RecommendationSprintPresentation.durationMinutes(estimateMinutes: 15, availableMinutes: 20) == nil)
    #expect(RecommendationSprintPresentation.sentence(
        taskTitle: "Prepare migration plan",
        sprintMinutes: 20,
        availableMinutes: 20
    ).contains("task will stay incomplete"))
}

@Test
func legacyRecommendationDecodesWithoutASuggestedSprint() throws {
    let data = Data(#"{"taskID":"task","sentence":"Start now.","reasons":["shortFit"]}"#.utf8)

    let recommendation = try JSONDecoder().decode(NextTaskRecommendation.self, from: data)

    #expect(recommendation.taskID == "task")
    #expect(recommendation.suggestedSprintMinutes == nil)
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
func gamingStatusUsesTheRecordedRewardAmountAndTruthfulFlexibleCopy() {
    let coverage = TelemetryCoverage(
        isLimited: false,
        explanation: "Current",
        lastObservationAt: Date()
    )
    let calculator = GamingStatusCalculator()

    let switchedPolicy = calculator.status(
        policy: .firm,
        gamingMinutes: 0,
        appliedRewardMinutes: 15,
        coverage: coverage
    )
    let flexible = calculator.status(
        policy: .flexible,
        gamingMinutes: 0,
        appliedRewardMinutes: nil,
        coverage: coverage
    )

    #expect(switchedPolicy.unlockedRemainingMinutes == 45)
    #expect(flexible.unlockedRemainingMinutes == 90)
    #expect(flexible.nextUnlockReason == "This policy uses a fixed daily gaming budget.")
}

@Test
func briefGamingTransitionDoesNotConsumeAllowanceButMeaningfulSessionDoes() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let observations = [
        BehaviorObservation(observedAt: start, application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(60), application: "Xcode", classification: .work),
        BehaviorObservation(observedAt: start.addingTimeInterval(120), application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(180), application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(240), application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(300), application: "Xcode", classification: .work)
    ]

    let result = BehaviorSessionizer().summarize(observations: observations, now: start.addingTimeInterval(360))

    #expect(result.summary.gamingMinutes == 4)
    #expect(result.summary.meaningfulGamingMinutes == 3)
    #expect(result.summary.workMinutes == 2)
}

@Test
func gamingStatusSeparatesBaseEarnedLockedRemainingAndSameDayOverage() {
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    let policy = GamingPolicy(dailyBudgetMinutes: 60, priorityTaskRewardMinutes: 15)

    let earned = GamingStatusCalculator().status(
        policy: policy,
        gamingMinutes: 80,
        appliedRewardMinutes: 15,
        coverage: coverage
    )
    #expect(earned.budgetMinutes == 60)
    #expect(earned.earnedMinutes == 15)
    #expect(earned.usedMinutes == 80)
    #expect(earned.lockedMinutes == 0)
    #expect(earned.unlockedRemainingMinutes == 0)
    #expect(earned.overageMinutes == 5)
    #expect(earned.allowanceBreakdown == "Base 60m · Earned 15m · Used 80m · Locked 0m · Remaining 0m · Same-day overage 5m")

    let locked = GamingStatusCalculator().status(
        policy: policy,
        gamingMinutes: 80,
        appliedRewardMinutes: nil,
        coverage: coverage
    )
    #expect(locked.earnedMinutes == 0)
    #expect(locked.lockedMinutes == 15)
    #expect(locked.overageMinutes == 20)
}

@Test
func legacyGamingAndBehaviorSnapshotsDecodeWithoutLosingObservedMinutes() throws {
    let gaming = try JSONDecoder().decode(
        GamingStatus.self,
        from: Data(#"{"budgetMinutes":60,"usedMinutes":7,"unlockedRemainingMinutes":53,"nextUnlockReason":"Legacy","confidenceIsLimited":false}"#.utf8)
    )
    #expect(gaming.earnedMinutes == 0)
    #expect(gaming.lockedMinutes == 0)
    #expect(gaming.overageMinutes == 0)
    #expect(gaming.budgetEnabled)

    let behavior = try JSONDecoder().decode(
        BehaviorSummary.self,
        from: Data(#"{"workMinutes":12,"gamingMinutes":7,"distractingMinutes":0,"idleMinutes":0,"unknownMinutes":0}"#.utf8)
    )
    #expect(behavior.gamingMinutes == 7)
    #expect(behavior.meaningfulGamingMinutes == 7)
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
    #expect(result.summary.appUsage.map(\.application) == ["Xcode", "ScreenSaver", "Steam", "Unknown application", "YouTube"])
    #expect(result.summary.appUsage.first?.percentage == 20)
    #expect(result.summary.appUsage.first?.classification == .work)
}

@Test
func appUsagePercentagesUseObservedSessionTimeAndSortLargestFirst() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let observations = [
        BehaviorObservation(observedAt: start, application: "Xcode", classification: .work),
        BehaviorObservation(observedAt: start.addingTimeInterval(120), application: "Safari", classification: .unknown),
        BehaviorObservation(observedAt: start.addingTimeInterval(180), application: "Xcode", classification: .work)
    ]

    let result = BehaviorSessionizer().summarize(
        observations: observations,
        now: start.addingTimeInterval(240),
        staleAfter: 1_000
    )

    #expect(result.summary.appUsage.map(\.application) == ["Xcode", "Safari"])
    #expect(result.summary.appUsage[0].observedSeconds == 180)
    #expect(abs(result.summary.appUsage[0].percentage - 75) < 0.001)
    #expect(abs(result.summary.appUsage[1].percentage - 25) < 0.001)
    #expect(result.summary.appUsage.map(\.classification) == [.work, .unknown])
}

@Test
func categoryUsageGroupsAppsAndPreservesOneHundredPercentTotal() {
    let summary = BehaviorSummary(appUsage: [
        AppUsageBreakdown(application: "Xcode", observedSeconds: 180, percentage: 50, classification: .work),
        AppUsageBreakdown(application: "Safari", observedSeconds: 90, percentage: 25, classification: .work),
        AppUsageBreakdown(application: "Steam", observedSeconds: 90, percentage: 25, classification: .gaming)
    ])

    #expect(summary.categoryUsage.map(\.classification) == [.work, .gaming])
    #expect(summary.categoryUsage.map(\.observedSeconds) == [270, 90])
    #expect(summary.categoryUsage.map(\.percentage) == [75, 25])
    #expect(summary.categoryUsage.reduce(0) { $0 + $1.percentage } == 100)
}

@Test
func gamingAllowanceUsesOnlyClassifiedGamingTime() {
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    let summary = BehaviorSummary(workMinutes: 10, gamingMinutes: 12, distractingMinutes: 25, idleMinutes: 0, unknownMinutes: 0)

    let status = GamingStatusCalculator().status(policy: GamingPolicy(), gamingMinutes: summary.meaningfulGamingMinutes, rewardApplied: false, coverage: coverage)

    #expect(summary.gamingOrDistractingMinutes == 37)
    #expect(status.usedMinutes == 12)
    #expect(status.unlockedRemainingMinutes == 48)
}

@Test
func gamingObservationModeKeepsFactsWithoutInventingABudget() {
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    let status = GamingStatusCalculator().status(
        policy: GamingPolicy(dailyBudgetMinutes: 60, priorityTaskRewardMinutes: 15, budgetEnabled: false),
        gamingMinutes: 42,
        rewardApplied: true,
        coverage: coverage
    )
    #expect(!status.budgetEnabled)
    #expect(status.usedMinutes == 42)
    #expect(status.budgetMinutes == 0)
    #expect(status.unlockedRemainingMinutes == 0)
    #expect(status.nextUnlockReason.contains("Observation only"))
}

@Test
func explicitAppClassificationOverridesBuiltInRulesWithoutUsingPartialMatches() {
    let classifier = BehaviorClassifier(
        policy: BehaviorPolicy(
            workApplications: ["Steam"],
            gamingApplications: ["Xcode"]
        )
    )

    #expect(classifier.classify(application: " steam ") == .work)
    #expect(classifier.classify(application: "XCODE") == .gaming)
    #expect(classifier.classify(application: "Steam Helper") == .gaming)
    #expect(classifier.classify(application: "Xcode Preview") == .work)
}

@Test
func communicationAppRulesOverrideBuiltInGamingAndCountAsWorkAtRuntime() {
    let classifier = BehaviorClassifier(
        policy: BehaviorPolicy(communicationApplications: ["Discord"])
    )

    #expect(classifier.classify(application: "DISCORD") == .work)
    #expect(classifier.classify(application: "Discord Helper") == .gaming)
}

@Test
func gamingToWorkPolicyBoundaryPreservesEarlierGamingUsageAndLabelsBothSessions() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let observations = [
        BehaviorObservation(observedAt: start, application: "Steam", classification: .gaming),
        BehaviorObservation(observedAt: start.addingTimeInterval(60), application: "Steam", classification: .work),
        BehaviorObservation(observedAt: start.addingTimeInterval(120), application: "Xcode", classification: .work)
    ]

    let result = BehaviorSessionizer().summarize(
        observations: observations,
        now: start.addingTimeInterval(180),
        staleAfter: 1_000
    )
    let gaming = GamingStatusCalculator().status(
        policy: GamingPolicy(),
        gamingMinutes: result.summary.meaningfulGamingMinutes,
        rewardApplied: false,
        coverage: result.coverage
    )

    #expect(result.summary.gamingMinutes == 1)
    #expect(result.summary.meaningfulGamingMinutes == 0)
    #expect(result.summary.workMinutes == 2)
    #expect(result.summary.appUsage.filter { $0.application == "Steam" }.map(\.classification) == [.work, .gaming])
    #expect(gaming.usedMinutes == 0)
    #expect(gaming.unlockedRemainingMinutes == 60)
}
