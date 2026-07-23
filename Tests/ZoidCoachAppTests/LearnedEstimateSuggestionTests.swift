import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func learnedEstimateAppearsOnlyAfterEnoughEligibleHistoryAndSurvivesRestart() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-learned-estimate-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
    let day = Date(timeIntervalSince1970: 1_752_408_000)
    let context = EstimateLearningContext(taskType: "write", project: "Work")
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "proposal",
            title: "Write proposal",
            dueDate: day,
            priority: 9,
            listID: "work",
            listName: "Work"
        )
    ])
    try AutonomousPlanStore(databaseURL: url).replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(
                    taskID: "proposal",
                    title: "Write proposal",
                    rank: 1,
                    estimateMinutes: 30,
                    reason: "Due today",
                    score: 100
                )
            ],
            mainObjectiveTaskID: "proposal",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 90
        ),
        for: day
    )
    let learning = try LearningAggregateStore(databaseURL: url, now: { day })
    for (index, actualMinutes) in [40, 45, 50].enumerated() {
        _ = try learning.recordEstimateSample(
            EstimateLearningSample(
                id: "history-\(index)",
                context: context,
                estimatedMinutes: 30,
                actualAlignedMinutes: actualMinutes,
                trackingCoverage: 1,
                completedAt: day.addingTimeInterval(Double(index - 10) * 86_400)
            )
        )
    }
    #expect(try learning.updateEstimateAggregate(context: context, currentEstimateMinutes: 30) == nil)
    #expect(try TodayDashboardAgent(databaseURL: url).snapshot(now: day).taskRows[0].learnedEstimateSuggestion == nil)

    _ = try learning.recordEstimateSample(
        EstimateLearningSample(
            id: "history-3",
            context: context,
            estimatedMinutes: 30,
            actualAlignedMinutes: 55,
            trackingCoverage: 1,
            completedAt: day.addingTimeInterval(-86_400)
        )
    )
    let proposal = try learning.updateEstimateAggregate(context: context, currentEstimateMinutes: 30)
    _ = try #require(proposal)

    let row = try TodayDashboardAgent(databaseURL: url).snapshot(now: day).taskRows[0]
    let suggestion = try #require(row.learnedEstimateSuggestion)
    #expect(row.estimateMinutes == 30)
    #expect(suggestion.recommendedMinutes == 50)
    #expect(suggestion.sampleCount == 4)
    #expect(suggestion.minimumActualMinutes == 40)
    #expect(suggestion.maximumActualMinutes == 55)
    #expect(suggestion.hasLimitedEvidence)

    let restarted = try TodayDashboardAgent(databaseURL: url).snapshot(now: day.addingTimeInterval(60))
    #expect(restarted.taskRows[0].estimateMinutes == 30)
    #expect(restarted.taskRows[0].learnedEstimateSuggestion == suggestion)
}

@Test
func learnedEstimatePresentationIsExplicitlyAdvisoryAndSupportsUseOrKeep() {
    let suggestion = LearnedEstimateSuggestion(
        recommendedMinutes: 50,
        sampleCount: 4,
        minimumActualMinutes: 40,
        maximumActualMinutes: 55,
        confidence: 0.34
    )
    let presentation = LearnedEstimateSuggestionPresentation(
        suggestion: suggestion,
        currentEstimateMinutes: 30
    )

    #expect(presentation.confidenceLabel == "EARLY PATTERN")
    #expect(presentation.evidenceText == "Based on 4 similar completed tasks. Actual aligned work ranged from 40 to 55 minutes.")
    #expect(presentation.keepLabel == "KEEP 30 MIN")
    #expect(presentation.statusText(for: .undecided) == nil)
    #expect(presentation.statusText(for: .used(50)) == "USED 50 MIN - YOU CAN STILL CHOOSE A DIFFERENT ESTIMATE")
    #expect(presentation.statusText(for: .keptOriginal) == "KEPT YOUR 30 MIN ESTIMATE")
}

@Test
func learnedEstimatePresentationNamesEstablishedEvidenceAndUnknownChoice() {
    let suggestion = LearnedEstimateSuggestion(
        recommendedMinutes: 45,
        sampleCount: 10,
        minimumActualMinutes: 35,
        maximumActualMinutes: 60,
        confidence: 0.83
    )
    let presentation = LearnedEstimateSuggestionPresentation(
        suggestion: suggestion,
        currentEstimateMinutes: nil
    )

    #expect(presentation.confidenceLabel == "ESTABLISHED PATTERN")
    #expect(presentation.keepLabel == "KEEP UNKNOWN")
    #expect(presentation.statusText(for: .keptOriginal) == "KEPT ESTIMATE AS UNKNOWN")
}

@Test
func todayTaskRowWithoutLearningSuggestionRemainsCodable() throws {
    let row = TodayTaskRow(
        taskID: "legacy",
        title: "Legacy task",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: .ready
    )

    let data = try JSONEncoder().encode(row)
    let decoded = try JSONDecoder().decode(TodayTaskRow.self, from: data)

    #expect(decoded == row)
    #expect(decoded.learnedEstimateSuggestion == nil)
}
