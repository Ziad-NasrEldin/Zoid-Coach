import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func estimateLearningPersistsEvidencePolicyConfidenceAndRollbackAcrossReopen() throws {
    let databaseURL = temporaryLearningDatabaseURL("estimate")
    defer { removeLearningDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_783_300_000)
    let context = EstimateLearningContext(taskType: "writing", project: "Zoid")
    let policy = EstimateLearningPolicy(version: 8, minimumSamples: 4, rollingSampleLimit: 8)
    do {
        let store = try LearningAggregateStore(databaseURL: databaseURL, now: { now })
        for (index, actual) in [40, 45, 50, 55].enumerated() {
            let sample = EstimateLearningSample(
                id: "estimate-\(index)",
                context: context,
                estimatedMinutes: 30,
                actualAlignedMinutes: actual,
                trackingCoverage: 0.95,
                completedAt: now.addingTimeInterval(TimeInterval(index))
            )
            #expect(try store.recordEstimateSample(sample, evidenceID: "event-\(index)"))
            #expect(try store.recordEstimateSample(sample, evidenceID: "event-\(index)") == false)
        }

        let proposal = try store.updateEstimateAggregate(
            context: context,
            currentEstimateMinutes: 60,
            policy: policy
        )

        #expect(proposal?.recommendedEstimateMinutes == 95)
        #expect(proposal?.rollbackEstimateMinutes == 60)
        #expect(proposal?.policyVersion == 8)
        #expect(proposal?.evidenceIDs == ["estimate-3", "estimate-2", "estimate-1", "estimate-0"])
    }

    let reopened = try LearningAggregateStore(databaseURL: databaseURL, now: { now })
    let stored = try reopened.estimateAggregate(for: context)
    #expect(stored?.proposal.recommendedEstimateMinutes == 95)
    #expect(stored?.proposal.evidenceIDs.count == 4)
    #expect(stored?.evidenceIDs == ["event-3", "event-2", "event-1", "event-0"])
    #expect(stored?.confidence == 0.5)
    #expect(try reopened.learnedEstimate(for: context, fallbackMinutes: 30) == 95)
    #expect(try reopened.rollbackEstimate(for: context) == 60)
}

@Test
func estimateSamplesAreImmutableAndSparseEvidenceDoesNotCreateAnAggregate() throws {
    let databaseURL = temporaryLearningDatabaseURL("immutable")
    defer { removeLearningDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_783_300_000)
    let context = EstimateLearningContext(taskType: "coding", project: nil)
    let store = try LearningAggregateStore(databaseURL: databaseURL, now: { now })
    let sample = EstimateLearningSample(
        id: "same-id",
        context: context,
        estimatedMinutes: 30,
        actualAlignedMinutes: 40,
        trackingCoverage: 0.9,
        completedAt: now
    )
    _ = try store.recordEstimateSample(sample)
    let conflicting = EstimateLearningSample(
        id: "same-id",
        context: context,
        estimatedMinutes: 30,
        actualAlignedMinutes: 90,
        trackingCoverage: 0.9,
        completedAt: now
    )

    #expect(throws: LearningAggregateStoreError.sampleConflict("same-id")) {
        try store.recordEstimateSample(conflicting)
    }
    #expect(try store.updateEstimateAggregate(context: context, currentEstimateMinutes: 30) == nil)
    #expect(try store.learnedEstimate(for: context, fallbackMinutes: 35) == 35)
}

@Test
func preferredWorkWindowPersistsTimezoneEvidenceAndRollback() throws {
    let databaseURL = temporaryLearningDatabaseURL("work-window")
    defer { removeLearningDatabaseFiles(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_783_300_000)
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let base = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    let rollback = WeeklyWorkWindow(
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
        start: LocalTime(hour: 8, minute: 0),
        end: LocalTime(hour: 17, minute: 0)
    )
    let store = try LearningAggregateStore(databaseURL: databaseURL, now: { now })
    for index in 0..<5 {
        let day = calendar.date(byAdding: .day, value: index, to: base)!
        let start = calendar.date(bySettingHour: 9, minute: 10 + index * 5, second: 0, of: day)!
        let sample = WorkWindowLearningSample(
            id: "window-\(index)",
            startedAt: start,
            endedAt: calendar.date(byAdding: .minute, value: 60 + index * 5, to: start)!,
            trackingCoverage: 0.95
        )
        _ = try store.recordWorkWindowSample(
            sample,
            timeZoneIdentifier: timeZone.identifier,
            evidenceID: "behavior-\(index)"
        )
    }

    let proposal = try store.updatePreferredWorkWindowAggregate(
        timeZoneIdentifier: timeZone.identifier,
        rollbackWindow: rollback,
        policy: PreferredWorkWindowLearningPolicy(version: 6, minimumSamples: 5, rollingSampleLimit: 10)
    )
    let stored = try store.preferredWorkWindowAggregate(timeZoneIdentifier: timeZone.identifier)

    #expect(proposal?.preferredWindow.start == LocalTime(hour: 9, minute: 20))
    #expect(proposal?.preferredWindow.end == LocalTime(hour: 10, minute: 30))
    #expect(proposal?.policyVersion == 6)
    #expect(proposal?.evidenceIDs.count == 5)
    #expect(stored?.evidenceIDs == ["behavior-4", "behavior-3", "behavior-2", "behavior-1", "behavior-0"])
    #expect(stored?.confidence == 0.5)
    #expect(try store.rollbackWorkWindow(timeZoneIdentifier: timeZone.identifier) == rollback)
}

private func temporaryLearningDatabaseURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-learning-\(label)-\(UUID().uuidString).sqlite")
}

private func removeLearningDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
