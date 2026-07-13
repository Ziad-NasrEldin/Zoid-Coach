import Foundation
import SQLite3
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func dailyReviewGroupsCoveredActivityWithoutExposingPrivateFields() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    try fixture.insert(epoch: 1_783_663_260, app: "Cursor", classification: .work)
    try fixture.insert(epoch: 1_783_663_900, app: "Steam", classification: .gaming)

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.sessions.count == 2)
    #expect(snapshot.sessions[0].application == "Cursor")
    #expect(snapshot.sessions[0].observationCount == 2)
    #expect(snapshot.sessions[1].classification == .gaming)
    #expect(snapshot.totals.first { $0.classification == .work }?.minutes == 2)
    #expect(snapshot.totals.first { $0.classification == .gaming }?.minutes == 1)
    #expect(snapshot.plannedTasks.isEmpty)
    #expect(snapshot.mainObjective == nil)
    #expect(snapshot.completedPriorityTaskCount == 0)
}

@Test
func dailyReviewKeepsCompletedTasksVisibleAfterTheyLeaveTheActiveList() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let completedAt = formatter.date(from: fixture.sourceDay)!.addingTimeInterval(12 * 3_600)
    let history = try TaskHistoryStore(databaseURL: fixture.databaseURL)
    try history.record(
        taskID: "reminder:launch",
        state: .completed,
        title: "Ship the launch brief",
        sourceKind: .reminders,
        at: completedAt
    )

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.completedTasks.count == 1)
    #expect(snapshot.completedTasks[0].title == "Ship the launch brief")
    #expect(snapshot.completedTasks[0].sourceKind == .reminders)
    #expect(snapshot.sessions.isEmpty)
}

@Test
func dailyReviewShowsMainObjectiveAndSameDayPriorityCompletionAcrossRestart() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insertPlanTask(id: "main-1", title: "Ship the client proposal", rank: 1, isMainObjective: true, estimateMinutes: 90)
    try fixture.insertPlanTask(id: "priority-2", title: "Send project notes", rank: 2, isMainObjective: false, estimateMinutes: 30)
    try fixture.insertPlanTask(id: "optional-3", title: "Tidy downloads", rank: 3, isMainObjective: false, estimateMinutes: 10, isOptional: true)
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let sourceDate = try #require(formatter.date(from: fixture.sourceDay))
    let history = try TaskHistoryStore(databaseURL: fixture.databaseURL)
    try history.record(taskID: "main-1", state: .completed, title: "Ship the client proposal", sourceKind: .local, at: sourceDate.addingTimeInterval(12 * 3_600))
    try history.record(taskID: "priority-2", state: .completed, title: "Send project notes", sourceKind: .local, at: sourceDate.addingTimeInterval(36 * 3_600))
    try history.record(taskID: "optional-3", state: .completed, title: "Tidy downloads", sourceKind: .local, at: sourceDate.addingTimeInterval(13 * 3_600))

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.plannedTasks.map(\.taskID) == ["main-1", "priority-2"])
    #expect(snapshot.mainObjective?.title == "Ship the client proposal")
    #expect(snapshot.mainObjective?.isCompleted == true)
    #expect(snapshot.completedPriorityTaskCount == 1)
    #expect(snapshot.plannedTasks[0].estimatedMinutes == 90)
    #expect(snapshot.plannedTasks[1].isCompleted == false)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).plannedTasks == snapshot.plannedTasks)
}

@Test
func dailyReviewShowsCorrectionAwareHighlightsAndBehaviorCoachingResponsesAcrossRestart() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    let workStart: Int64 = 1_783_663_200
    for offset in 0..<5 {
        try fixture.insert(epoch: workStart + Int64(offset * 60), app: "YouTube", classification: .gaming)
    }
    let driftStart = workStart + 20 * 60
    for offset in 0..<3 {
        try fixture.insert(epoch: driftStart + Int64(offset * 60), app: "Steam", classification: .gaming)
    }
    let laterWorkStart = workStart + 40 * 60
    for offset in 0..<5 {
        try fixture.insert(epoch: laterWorkStart + Int64(offset * 60), app: "Xcode", classification: .work)
    }
    let initial = try fixture.store.load(sourceDay: fixture.sourceDay)
    let correctedSession = try #require(initial.sessions.first { $0.application == "YouTube" })
    try fixture.store.correct(correctedSession, to: .work, taskID: "main-1", from: nil)

    let dayFormatter = DateFormatter()
    dayFormatter.calendar = .current
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.timeZone = .current
    dayFormatter.dateFormat = "yyyy-MM-dd"
    let sourceDate = try #require(dayFormatter.date(from: fixture.sourceDay))
    do {
        let promptStore = try PromptInboxStore(
            databaseURL: fixture.databaseURL,
            now: { sourceDate.addingTimeInterval(10 * 3_600) }
        )
        let gaming = try promptStore.enqueue(PromptDraft(
            decisionKey: "review-gaming",
            type: "GAMING_DRIFT",
            title: "Ready to return?",
            summary: "Observed gaming while the main task remained open.",
            actions: [PromptAction(kind: .continueIntentionally, title: "Continue intentionally")],
            payload: [
                "application": "Steam",
                "observedGamingMinutes": "12",
                "taskID": "main-1",
                "taskTitle": "Ship the client proposal"
            ]
        )).episode
        let response = try promptStore.respond(
            promptID: gaming.id,
            action: .continueIntentionally,
            actionToken: PromptResponseToken.make(promptID: gaming.id, action: .continueIntentionally),
            surface: .dashboard
        )
        try promptStore.markEffectApplied(responseID: response.response.id)
    }
    do {
        let promptStore = try PromptInboxStore(
            databaseURL: fixture.databaseURL,
            now: { sourceDate.addingTimeInterval(11 * 3_600) }
        )
        _ = try promptStore.enqueue(PromptDraft(
            decisionKey: "review-wake",
            type: "WAKE_INTERVENTION",
            title: "Ready to continue?",
            summary: "The active task is still available.",
            actions: [PromptAction(kind: .startRecommendedTask, title: "Start task")]
        ))
        _ = try promptStore.enqueue(PromptDraft(
            decisionKey: "review-plan",
            type: "PLAN_READY",
            title: "Plan ready",
            summary: "This planning prompt is not a behavior intervention.",
            actions: [PromptAction(kind: .acceptPlan, title: "Accept")]
        ))
    }
    do {
        let promptStore = try PromptInboxStore(
            databaseURL: fixture.databaseURL,
            now: { sourceDate.addingTimeInterval(12 * 3_600) }
        )
        let recovery = try promptStore.enqueue(PromptDraft(
            decisionKey: "review-recovery-observed",
            type: "GAMING_DRIFT",
            title: "Ready to return?",
            summary: "Observed 10 minutes in Steam while the proposal remained unfinished.",
            actions: [PromptAction(kind: .startWorkSprint, title: "Start a 20-minute work sprint")],
            payload: [
                "application": "Steam",
                "observedGamingMinutes": "10",
                "taskID": "main-1",
                "taskTitle": "Ship the client proposal"
            ]
        )).episode
        let response = try promptStore.respond(
            promptID: recovery.id,
            action: .startWorkSprint,
            actionToken: PromptResponseToken.make(promptID: recovery.id, action: .startWorkSprint),
            surface: .notification
        )
        try promptStore.markEffectApplied(responseID: response.response.id)
        let followThroughStart = Int64(sourceDate.addingTimeInterval(12 * 3_600 + 5 * 60).timeIntervalSince1970)
        for offset in 0..<3 {
            try fixture.insert(
                epoch: followThroughStart + Int64(offset * 60),
                app: "Xcode",
                classification: .work
            )
        }
        for offset in 0..<2 {
            try fixture.insert(
                epoch: followThroughStart + 10 * 60 + Int64(offset * 60),
                app: "Notes",
                classification: .work
            )
        }
        let withFollowThrough = try fixture.store.load(sourceDay: fixture.sourceDay)
        let followThrough = try #require(withFollowThrough.sessions.first {
            $0.application == "Xcode" && $0.start.timeIntervalSince1970 >= Double(followThroughStart)
        })
        try fixture.store.correct(followThrough, to: .work, taskID: "main-1", from: nil)
    }
    do {
        let promptStore = try PromptInboxStore(
            databaseURL: fixture.databaseURL,
            now: { sourceDate.addingTimeInterval(13 * 3_600) }
        )
        let recovery = try promptStore.enqueue(PromptDraft(
            decisionKey: "review-recovery-unobserved",
            type: "GAMING_DRIFT",
            title: "Ready to return?",
            summary: "The selected task remains available.",
            actions: [PromptAction(kind: .returnToActiveTask, title: "Return to the task")],
            payload: ["taskID": "main-1", "taskTitle": "Ship the client proposal"]
        )).episode
        let response = try promptStore.respond(
            promptID: recovery.id,
            action: .returnToActiveTask,
            actionToken: PromptResponseToken.make(promptID: recovery.id, action: .returnToActiveTask),
            surface: .dashboard
        )
        try promptStore.markEffectApplied(responseID: response.response.id)
    }

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let snapshot = try reopened.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.bestObservedWorkBlock?.application == "YouTube")
    #expect(snapshot.bestObservedWorkBlock?.durationMinutes == 5)
    #expect(snapshot.largestObservedDriftEpisode?.application == "Steam")
    #expect(snapshot.largestObservedDriftEpisode?.durationMinutes == 3)
    #expect(snapshot.coachingInteractions.count == 4)
    #expect(snapshot.coachingInteractions[0].promptType == "GAMING_DRIFT")
    #expect(snapshot.coachingInteractions[0].responseAction == PromptActionKind.continueIntentionally.rawValue)
    #expect(snapshot.coachingInteractions[0].responseSurface == PromptSurface.dashboard.rawValue)
    #expect(snapshot.coachingInteractions[0].effectWasApplied == true)
    #expect(snapshot.coachingInteractions[0].observedApplication == "Steam")
    #expect(snapshot.coachingInteractions[0].observedGamingMinutes == 12)
    #expect(snapshot.coachingInteractions[0].unfinishedTaskTitle == "Ship the client proposal")
    #expect(snapshot.coachingInteractions[0].outcome == .intentionalChoice)
    #expect(snapshot.coachingInteractions[1].promptType == "WAKE_INTERVENTION")
    #expect(snapshot.coachingInteractions[1].responseAction == nil)
    #expect(snapshot.coachingInteractions[1].effectWasApplied == nil)
    #expect(snapshot.coachingInteractions[1].outcome == .unanswered)
    #expect(snapshot.coachingInteractions[2].responseAction == PromptActionKind.startWorkSprint.rawValue)
    #expect(snapshot.coachingInteractions[2].responseSurface == PromptSurface.notification.rawValue)
    #expect(snapshot.coachingInteractions[2].outcome == .returnedToWork(observedMinutes: 3, selectedTaskMatched: true))
    #expect(snapshot.coachingInteractions[3].outcome == .recoveryStarted)
}

@Test
func dailyReviewSummarizesPostCapDriftWithoutInventingPrompts() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insertQuietDrift(
        startedAtEpoch: 1_783_663_200,
        latestAtEpoch: 1_783_663_860,
        application: "Steam",
        observedMinutes: 12
    )
    try fixture.insertQuietDrift(
        startedAtEpoch: 1_783_665_000,
        latestAtEpoch: 1_783_666_140,
        application: "GeForce NOW",
        observedMinutes: 20
    )

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.coachingInteractions.isEmpty)
    #expect(snapshot.quietDrift == DailyReviewQuietDriftSummary(
        episodeCount: 2,
        totalObservedMinutes: 32,
        largestEpisodeMinutes: 20,
        applications: ["Steam", "GeForce NOW"]
    ))

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).quietDrift == snapshot.quietDrift)
    #expect(try reopened.load(sourceDay: "2026-07-11").quietDrift == nil)
}

@Test
func dailyReviewHighlightUsesExactDurationBeforeRoundedDisplayMinutes() {
    let start = Date(timeIntervalSince1970: 1_783_663_200)
    let earlier = DailyReviewSession(
        sourceDay: "2026-07-10",
        start: start,
        end: start.addingTimeInterval(241),
        application: "Earlier",
        classification: .work,
        observationCount: 5
    )
    let laterStart = start.addingTimeInterval(600)
    let later = DailyReviewSession(
        sourceDay: "2026-07-10",
        start: laterStart,
        end: laterStart.addingTimeInterval(299),
        application: "Later",
        classification: .work,
        observationCount: 5
    )
    let snapshot = DailyReviewSnapshot(
        sourceDay: "2026-07-10",
        sessions: [earlier, later],
        totals: [],
        hypothesis: nil,
        hypothesisState: .pending,
        confirmedAt: nil
    )

    #expect(earlier.durationMinutes == later.durationMinutes)
    #expect(snapshot.bestObservedWorkBlock?.application == "Later")
}

@Test
func unknownSessionReviewSeparatesPendingEvidenceWithoutChangingItsClassification() {
    let sourceDay = "2026-07-10"
    let unknownLater = DailyReviewSession(
        sourceDay: sourceDay,
        start: Date(timeIntervalSince1970: 1_783_663_320),
        end: Date(timeIntervalSince1970: 1_783_663_440),
        application: "Preview",
        classification: .unknown,
        observationCount: 2
    )
    let known = DailyReviewSession(
        sourceDay: sourceDay,
        start: Date(timeIntervalSince1970: 1_783_663_260),
        end: Date(timeIntervalSince1970: 1_783_663_320),
        application: "Cursor",
        classification: .work,
        observationCount: 1
    )
    let unknownEarlier = DailyReviewSession(
        sourceDay: sourceDay,
        start: Date(timeIntervalSince1970: 1_783_663_200),
        end: Date(timeIntervalSince1970: 1_783_663_260),
        application: "Safari",
        classification: .unknown,
        observationCount: 1
    )

    let state = UnknownSessionReviewState(
        sessions: [unknownLater, known, unknownEarlier]
    )

    #expect(state.hasPending)
    #expect(state.pending.map(\.application) == ["Safari", "Preview"])
    #expect(state.pending.allSatisfy { $0.classification == .unknown })
    #expect(state.pendingMinutes == 3)
    #expect(state.classified == [known])
    #expect(!UnknownSessionReviewState(sessions: [known]).hasPending)
}

@Test
func correctionAndTaskAttachmentPersistAndRecalculateTotalsAfterRestart() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "YouTube", classification: .distracting)
    try fixture.insert(epoch: 1_783_663_260, app: "YouTube", classification: .distracting)
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.correct(original, to: .work, taskID: "Write proposal", from: nil)
    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let corrected = try reopened.load(sourceDay: fixture.sourceDay)

    #expect(corrected.sessions.count == 1)
    #expect(corrected.sessions[0].classification == .work)
    #expect(corrected.sessions[0].taskID == "Write proposal")
    #expect(corrected.totals == [DailyReviewTotal(classification: .work, minutes: 2)])
}

@Test
func correctingUnknownSessionClearsReviewQueueAndPersistsScopedFutureRule() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { fixedNow })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Safari", classification: .unknown)
    try fixture.insert(epoch: 1_783_663_260, app: "Safari", classification: .unknown)
    try fixture.insert(epoch: 1_783_663_900, app: "Cursor", classification: .work)
    var state = UnknownSessionReviewState(
        sessions: try fixture.store.load(sourceDay: fixture.sourceDay).sessions
    )
    let pending = try #require(state.pending.first)

    try fixture.store.correct(
        pending,
        to: .work,
        taskID: "Research",
        applyToFuture: true
    )

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    state = UnknownSessionReviewState(
        sessions: try reopened.load(sourceDay: fixture.sourceDay).sessions
    )
    let rules = try reopened.classificationRules()
    #expect(!state.hasPending)
    #expect(state.classified.count == 2)
    #expect(state.classified.first { $0.application == "Safari" }?.taskID == "Research")
    #expect(rules.count == 1)
    #expect(rules[0].normalizedApplication == "safari")
    #expect(rules[0].classification == .work)
}

@Test
func futureClassificationRulePersistsCanBeReplacedAndRemovedWithoutRewritingCorrection() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { fixedNow })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "YouTube", classification: .distracting)
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.correct(
        original,
        to: .work,
        taskID: "Research",
        applyToFuture: true
    )
    _ = try fixture.store.upsertClassificationRule(for: original, classification: .gaming)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    var rules = try reopened.classificationRules()
    let historical = try reopened.load(sourceDay: fixture.sourceDay)
    #expect(rules.count == 1)
    #expect(rules[0].application == "YouTube")
    #expect(rules[0].normalizedApplication == "youtube")
    #expect(rules[0].classification == .gaming)
    #expect(historical.sessions[0].classification == .work)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM app_classification_correction_rules;") == 2)

    try reopened.removeClassificationRule(normalizedApplication: "  YOUTUBE  ")
    rules = try reopened.classificationRules()
    #expect(rules.isEmpty)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM app_classification_correction_rules;") == 3)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).sessions[0].classification == .work)
}

@Test
func resetClassificationRulesTombstonesEveryActiveRuleAndPreservesHistoricalCorrections() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { fixedNow })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "YouTube", classification: .distracting)
    try fixture.insert(epoch: 1_783_663_900, app: "Steam", classification: .gaming)
    let sessions = try fixture.store.load(sourceDay: fixture.sourceDay).sessions
    try fixture.store.correct(sessions[0], to: .work, taskID: "Research", applyToFuture: true)
    try fixture.store.correct(sessions[1], to: .work, taskID: "Documentation", applyToFuture: true)

    #expect(try fixture.store.classificationRules().count == 2)
    #expect(try fixture.store.resetClassificationRules() == 2)
    #expect(try fixture.store.classificationRules().isEmpty)
    #expect(try fixture.store.resetClassificationRules() == 0)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM app_classification_correction_rules;") == 4)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let historical = try reopened.load(sourceDay: fixture.sourceDay)
    #expect(try reopened.classificationRules().isEmpty)
    #expect(historical.sessions.allSatisfy { $0.classification == .work })
    #expect(Set(historical.sessions.compactMap(\.taskID)) == Set(["Research", "Documentation"]))
}

@Test
func futureClassificationRuleRejectsIdleAndUnknownAsUnsafeAppDefaults() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Safari", classification: .unknown)
    let session = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.upsertClassificationRule(for: session, classification: .unknown)
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.upsertClassificationRule(for: session, classification: .idle)
    }
    #expect(throws: DailyReviewStoreError.self) {
        try fixture.store.correct(session, to: .unknown, applyToFuture: true)
    }
    #expect(try fixture.store.classificationRules().isEmpty)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM daily_review_corrections;") == 0)
}

@Test
func splitCorrectionChangesOnlyTheSecondHalfOfASession() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    for offset in [0, 60, 120, 180] {
        try fixture.insert(
            epoch: 1_783_663_200 + Int64(offset),
            app: "Safari",
            classification: .unknown
        )
    }
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]
    let midpoint = original.start.addingTimeInterval(original.end.timeIntervalSince(original.start) / 2)

    try fixture.store.correct(original, to: .work, taskID: "Research", from: midpoint)
    let corrected = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(corrected.sessions.count == 2)
    #expect(corrected.sessions.map(\.classification) == [.unknown, .work])
    #expect(corrected.sessions[0].taskID == nil)
    #expect(corrected.sessions[1].taskID == "Research")
}

@Test
func hypothesisDecisionAndConfirmationAreDurableAndCorrectionReopensReview() throws {
    let confirmationDate = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { confirmationDate })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Steam", classification: .gaming)
    let session = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.setHypothesisState(.rejected, sourceDay: fixture.sourceDay)
    try fixture.store.confirm(sourceDay: fixture.sourceDay)
    var snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.hypothesisState == .rejected)
    #expect(snapshot.confirmedAt == confirmationDate)

    try fixture.store.correct(session, to: .work, taskID: nil, from: nil)
    snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.hypothesisState == .pending)
    #expect(snapshot.confirmedAt == nil)
}

@Test
func unfinishedReviewSurvivesRestartAndDisappearsOnlyAfterConfirmation() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)

    let session = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]
    try fixture.store.correct(session, to: .distracting, taskID: nil, from: nil)

    let beforeRestartResult = try fixture.store.mostRecentUnfinishedReview()
    let beforeRestart = try #require(beforeRestartResult)
    #expect(beforeRestart.sourceDay == fixture.sourceDay)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let afterRestartResult = try reopened.mostRecentUnfinishedReview()
    let afterRestart = try #require(afterRestartResult)
    #expect(afterRestart.sourceDay == fixture.sourceDay)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).sessions[0].classification == .distracting)

    try reopened.confirm(sourceDay: fixture.sourceDay)
    #expect(try reopened.mostRecentUnfinishedReview() == nil)
}

@Test
func offlineWorkPersistsAcrossRestartAndRemainsSeparateFromObservedCoverage() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)

    let id = try fixture.store.saveOfflineWork(
        sourceDay: fixture.sourceDay,
        taskID: "Draft contract",
        startedAt: startedAt,
        durationMinutes: 45,
        note: "Client workshop"
    )
    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let snapshot = try reopened.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.count == 1)
    #expect(snapshot.offlineWork[0].id == id)
    #expect(snapshot.offlineWork[0].taskID == "Draft contract")
    #expect(snapshot.offlineWork[0].note == "Client workshop")
    #expect(snapshot.observedMinutes == 1)
    #expect(snapshot.offlineMinutes == 45)
    #expect(snapshot.actualMinutes == 46)
}

@Test
func offlineWorkCanBeCorrectedIdempotentlyAndReopensAConfirmedReview() throws {
    let confirmationDate = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { confirmationDate })
    defer { fixture.remove() }
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)
    let id = try fixture.store.saveOfflineWork(
        id: "offline-1",
        sourceDay: fixture.sourceDay,
        taskID: nil,
        startedAt: startedAt,
        durationMinutes: 20,
        note: "Unassigned work"
    )
    try fixture.store.confirm(sourceDay: fixture.sourceDay)

    _ = try fixture.store.saveOfflineWork(
        id: id,
        sourceDay: fixture.sourceDay,
        taskID: "Research",
        startedAt: startedAt,
        durationMinutes: 35,
        note: "Corrected after review"
    )
    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.count == 1)
    #expect(snapshot.offlineWork[0].durationMinutes == 35)
    #expect(snapshot.offlineWork[0].taskID == "Research")
    #expect(snapshot.confirmedAt == nil)
}

@Test
func offlineWorkValidatesDurationAndCanBeDeletedWithoutTouchingObservations() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)

    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: nil,
            startedAt: startedAt,
            durationMinutes: 0,
            note: nil
        )
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: "   ",
            startedAt: startedAt,
            durationMinutes: 15,
            note: "\n"
        )
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: String(repeating: "x", count: 201),
            startedAt: startedAt,
            durationMinutes: 15,
            note: nil
        )
    }
    let id = try fixture.store.saveOfflineWork(
        sourceDay: fixture.sourceDay,
        taskID: "Research",
        startedAt: startedAt,
        durationMinutes: 15,
        note: nil
    )
    try fixture.store.deleteOfflineWork(id: id, sourceDay: fixture.sourceDay)
    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.isEmpty)
    #expect(snapshot.observedMinutes == 1)
}

@Test
func migrationCreatesReviewTablesWithoutChangingBehaviorEvidence() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)

    let result = try AutonomousDatabaseMigrator(databaseURL: fixture.databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM behavior_records;") == 1)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('daily_reviews', 'daily_review_corrections', 'offline_work_entries');") == 3)
}

@Test
func personalReviewNoteTrimsPersistsReopensAndClearsWithoutChangingEvidence() throws {
    let fixture = try DailyReviewFixture(now: { Date(timeIntervalSince1970: 1_783_663_200) })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    try fixture.store.confirm(sourceDay: fixture.sourceDay)

    try fixture.store.savePersonalNote("  Client feedback changed the afternoon.  ", sourceDay: fixture.sourceDay)
    var snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.personalNote == "Client feedback changed the afternoon.")
    #expect(snapshot.confirmedAt == nil)
    #expect(snapshot.observedMinutes == 1)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).personalNote == "Client feedback changed the afternoon.")
    try reopened.savePersonalNote("   ", sourceDay: fixture.sourceDay)
    snapshot = try reopened.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.personalNote == nil)
    #expect(snapshot.observedMinutes == 1)

    #expect(throws: DailyReviewStoreError.self) {
        try reopened.savePersonalNote(String(repeating: "x", count: 1_001), sourceDay: fixture.sourceDay)
    }
}

private final class DailyReviewFixture {
    let databaseURL: URL
    let sourceDay = "2026-07-10"
    let store: DailyReviewStore

    init(now: @escaping @Sendable () -> Date = Date.init) throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-daily-review-\(UUID().uuidString).sqlite")
        store = try DailyReviewStore(databaseURL: databaseURL, now: now)
    }

    func insert(epoch: Int64, app: String, classification: BehaviorClassification) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES (?, ?, '09:00', ?, 'private title', 'https://private.example', 0, NULL, '2026-07-10T09:00:00Z', ?, 1);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceDay, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_int64(statement, 2, epoch)
        sqlite3_bind_text(statement, 3, app, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_text(statement, 4, classification.rawValue, -1, SQLITE_TRANSIENT_REVIEW)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DailyReviewTestError.database }
    }

    func insertPlanTask(
        id: String,
        title: String,
        rank: Int,
        isMainObjective: Bool,
        estimateMinutes: Int,
        isOptional: Bool = false
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var sourceStatement: OpaquePointer?
        let sourceSQL = "INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES (?, ?, 0, 0, '2026-07-10T08:00:00Z', 'local');"
        guard sqlite3_prepare_v2(database, sourceSQL, -1, &sourceStatement, nil) == SQLITE_OK,
              let sourceStatement else { throw DailyReviewTestError.database }
        sqlite3_bind_text(sourceStatement, 1, id, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_text(sourceStatement, 2, title, -1, SQLITE_TRANSIENT_REVIEW)
        guard sqlite3_step(sourceStatement) == SQLITE_DONE else {
            sqlite3_finalize(sourceStatement)
            throw DailyReviewTestError.database
        }
        sqlite3_finalize(sourceStatement)

        var planStatement: OpaquePointer?
        let planSQL = "INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional) VALUES (?, ?, ?, ?, ?, '2026-07-10T08:00:00Z', 'priority', 100, ?);"
        guard sqlite3_prepare_v2(database, planSQL, -1, &planStatement, nil) == SQLITE_OK,
              let planStatement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(planStatement) }
        sqlite3_bind_text(planStatement, 1, sourceDay, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_text(planStatement, 2, id, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_int(planStatement, 3, Int32(rank))
        sqlite3_bind_int(planStatement, 4, isMainObjective ? 1 : 0)
        sqlite3_bind_int(planStatement, 5, Int32(estimateMinutes))
        sqlite3_bind_int(planStatement, 6, isOptional ? 1 : 0)
        guard sqlite3_step(planStatement) == SQLITE_DONE else { throw DailyReviewTestError.database }
    }

    func insertQuietDrift(
        startedAtEpoch: Int64,
        latestAtEpoch: Int64,
        application: String,
        observedMinutes: Int
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO quiet_drift_episodes(local_day, session_started_epoch, latest_observed_epoch, application, observed_minutes, recorded_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, '2026-07-10T12:00:00Z', '2026-07-10T12:00:00Z');"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceDay, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_int64(statement, 2, startedAtEpoch)
        sqlite3_bind_int64(statement, 3, latestAtEpoch)
        sqlite3_bind_text(statement, 4, application, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_int(statement, 5, Int32(observedMinutes))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DailyReviewTestError.database }
    }

    func scalar(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DailyReviewTestError.database }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

private enum DailyReviewTestError: Error { case database }

private let SQLITE_TRANSIENT_REVIEW = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
