import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func gamingDriftStaysQuietUntilBaselineCompletesThenQueuesEvidenceFirstPrompt() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)

    #expect(try fixture.service.produce(
        policy: fixture.policy(),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline(completeDays: 6)
    ) == .suppressed(.observingBaseline))
    #expect(try fixture.promptStore.unresolved().isEmpty)

    let result = try fixture.service.produce(
        policy: fixture.policy(),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline(completeDays: 7)
    )
    guard case let .queued(episode, wasInserted) = result else {
        Issue.record("Expected a queued coaching prompt")
        return
    }
    #expect(wasInserted)
    #expect(episode.type == "GAMING_DRIFT")
    #expect(episode.summary.contains("10 observed minutes in Steam"))
    #expect(episode.summary.contains("Ship client proposal remains unfinished"))
    #expect(episode.summary.contains("not why it happened or what you intended"))
    #expect(episode.actions.first?.kind == .returnToActiveTask)
    #expect(episode.actions.first?.role == .primary)
    #expect(episode.actions.count == 6)
    #expect(episode.actions.filter { $0.role == .primary }.count == 1)
    #expect(episode.actions.filter { $0.role == .secondary }.count == 3)
    #expect(episode.actions.contains { $0.kind == .startShortSprint })
    #expect(episode.actions.contains {
        $0.kind == .rescheduleTask
            && $0.title == "Reschedule Ship client proposal"
            && $0.role == .destructive
            && $0.requiresConfirmation
    })
    #expect(episode.actions.contains {
        $0.kind == .markBlocked
            && $0.title == "Mark Ship client proposal blocked"
            && $0.role == .destructive
            && $0.requiresConfirmation
    })
    #expect(!episode.actions.contains { $0.kind == .startBreak })
    #expect(episode.payload["coachingLevel"] == CoachingLevel.gentle.rawValue)
    #expect(episode.payload["maximumInterventionLevel"] == CoachingLevel.gentle.rawValue)
    #expect(episode.payload["behaviorPromptContractVersion"] == BehaviorPromptPresentationPolicy.contractVersion)
    #expect(BehaviorPromptPresentationPolicy.issues(for: PromptDraft(
        decisionKey: episode.decisionKey,
        type: episode.type,
        title: episode.title,
        summary: episode.summary,
        actions: episode.actions,
        payload: episode.payload,
        expiresAt: episode.expiresAt
    )).isEmpty)
    #expect(try fixture.promptStore.unresolved().count == 1)

    let reopened = try PromptInboxStore(databaseURL: fixture.databaseURL, now: { fixture.clock.now })
    #expect(try reopened.unresolved().first?.id == episode.id)
}

@Test
func gamingDriftOffersBreakOnlyWhenATaskIsActivelyTracking() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let execution = try TaskExecutionStore(databaseURL: fixture.databaseURL)
    try execution.apply(.start, taskID: "active-1", at: fixture.clock.now.addingTimeInterval(-600))

    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: fixture.policy(level: .accountability),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected an accountability prompt")
        return
    }
    #expect(episode.actions.count == 6)
    #expect(episode.actions.filter { $0.role == .primary }.count == 1)
    #expect(episode.actions.contains { $0.kind == .startWorkSprint })
    #expect(episode.actions.contains { $0.kind == .rescheduleTask })
    #expect(episode.actions.contains { $0.kind == .markBlocked })
    #expect(episode.actions.contains { $0.kind == .startBreak && $0.title == "Take a break" })
    #expect(episode.payload["maximumInterventionLevel"] == CoachingLevel.accountability.rawValue)
}

@Test
func gamingDriftRequiresTenFreshCertainMinutesAndAnExhaustedAllowance() throws {
    let short = try GamingPromptFixture()
    defer { short.remove() }
    try short.insertPriorityTask()
    try short.insertGaming(minutes: 9)
    #expect(try short.service.produce(
        policy: short.policy(), gamingStatus: short.gamingStatus, baselineStatus: short.baseline()
    ) == .suppressed(.belowThreshold))

    let uncertain = try GamingPromptFixture()
    defer { uncertain.remove() }
    try uncertain.insertPriorityTask()
    try uncertain.insertGaming(minutes: 10)
    #expect(try uncertain.service.produce(
        policy: uncertain.policy(),
        gamingStatus: GamingStatus(
            budgetMinutes: 0,
            usedMinutes: 10,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "",
            confidenceIsLimited: true
        ),
        baselineStatus: uncertain.baseline()
    ) == .suppressed(.limitedCoverage))

    let unlocked = try GamingPromptFixture()
    defer { unlocked.remove() }
    try unlocked.insertPriorityTask()
    try unlocked.insertGaming(minutes: 10)
    #expect(try unlocked.service.produce(
        policy: unlocked.policy(),
        gamingStatus: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 10,
            unlockedRemainingMinutes: 50,
            nextUnlockReason: "",
            confidenceIsLimited: false
        ),
        baselineStatus: unlocked.baseline()
    ) == .suppressed(.gamingIsUnlocked))
}

@Test
func manuallyGrantedGamingAllowanceSuppressesDriftAfterAgentStoreRestart() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let request = GamingManualAdjustmentRequest(
        requestID: "gaming-adjustment-v1:prompt-suppression",
        day: fixture.clock.now,
        timeZoneIdentifier: "UTC",
        minutes: 15,
        note: "Intentional evening grant"
    )
    let writer = try GamingManualAdjustmentStore(databaseURL: fixture.databaseURL)
    _ = try writer.record(request)

    let restartedLedger = try GamingManualAdjustmentStore(databaseURL: fixture.databaseURL)
    let adjustedStatus = try restartedLedger.gamingStatus(
        applyingAdjustmentsFor: fixture.clock.now,
        timeZoneIdentifier: "UTC",
        to: fixture.gamingStatus
    )
    #expect(adjustedStatus.manualAdjustmentMinutes == 15)
    #expect(adjustedStatus.unlockedRemainingMinutes == 5)

    let restartedPromptStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: restartedPromptStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    #expect(try restartedService.produce(
        policy: fixture.policy(),
        gamingStatus: adjustedStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.gamingIsUnlocked))
    #expect(try restartedPromptStore.unresolved().isEmpty)
}

@Test
func gamingDriftHonorsPauseWorkWindowBreakEndDayAndIncompleteWorkGates() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)

    #expect(try fixture.service.produce(
        policy: fixture.policy(paused: true), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.automationPaused))
    #expect(try fixture.service.produce(
        policy: fixture.policy(workStart: LocalTime(hour: 12, minute: 0)),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.outsideWorkWindow))

    try fixture.insertOpenPause(.break)
    #expect(try fixture.service.produce(
        policy: fixture.policy(), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.acceptedBreak))
    try fixture.closePauses()
    try fixture.insertOpenPause(.endingWorkday)
    #expect(try fixture.service.produce(
        policy: fixture.policy(), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.workdayClosed))

    let noPlan = try GamingPromptFixture()
    defer { noPlan.remove() }
    try noPlan.insertGaming(minutes: 10)
    #expect(try noPlan.service.produce(
        policy: noPlan.policy(), gamingStatus: noPlan.gamingStatus, baselineStatus: noPlan.baseline()
    ) == .suppressed(.noIncompletePriorityWork))
}

@Test
func gamingDriftSuppressesPromptsWhenScreenwatchBecomesStaleAndRecoversWithFreshEvidence() throws {
    let missing = try GamingPromptFixture()
    defer { missing.remove() }
    try missing.insertPriorityTask()
    #expect(try missing.service.produce(
        policy: missing.policy(),
        gamingStatus: missing.gamingStatus,
        baselineStatus: missing.baseline()
    ) == .suppressed(.limitedCoverage))
    #expect(try missing.promptStore.unresolved().isEmpty)

    let lifecycle = try GamingPromptFixture()
    defer { lifecycle.remove() }
    try lifecycle.insertPriorityTask()
    try lifecycle.insertGaming(minutes: 10)
    lifecycle.advance(minutes: 15)
    #expect(try lifecycle.service.produce(
        policy: lifecycle.policy(),
        gamingStatus: lifecycle.gamingStatus,
        baselineStatus: lifecycle.baseline()
    ) == .suppressed(.limitedCoverage))
    #expect(try lifecycle.promptStore.unresolved().isEmpty)

    try lifecycle.insertGaming(minutes: 10)
    guard case let .queued(lifecyclePrompt, _) = try lifecycle.service.produce(
        policy: lifecycle.policy(),
        gamingStatus: lifecycle.gamingStatus,
        baselineStatus: lifecycle.baseline()
    ) else {
        Issue.record("Expected fresh Screenwatch evidence to restore behavior prompt eligibility")
        return
    }
    #expect(try lifecycle.promptStore.unresolved().count == 1)
    #expect(try lifecycle.service.produce(
        policy: lifecycle.policy(),
        gamingStatus: lifecycle.gamingStatus,
        baselineStatus: lifecycle.baseline()
    ) == .suppressed(.sessionAlreadyHandled))
    #expect(try lifecycle.promptStore.unresolved().count == 1)

    lifecycle.advance(minutes: 15)
    #expect(try lifecycle.service.produce(
        policy: lifecycle.policy(),
        gamingStatus: lifecycle.gamingStatus,
        baselineStatus: lifecycle.baseline()
    ) == .suppressed(.limitedCoverage))
    let reopened = try PromptInboxStore(databaseURL: lifecycle.databaseURL, now: { lifecycle.clock.now })
    #expect(try reopened.unresolved().isEmpty)
    #expect(try reopened.episode(promptID: lifecyclePrompt.id)?.resolutionOrigin == .system)
    #expect(try reopened.episode(promptID: lifecyclePrompt.id)?.resolutionReason == .screenwatchEvidenceInvalid)

    let exactBoundary = try GamingPromptFixture()
    defer { exactBoundary.remove() }
    try exactBoundary.insertPriorityTask()
    try exactBoundary.insertGaming(minutes: 10)
    exactBoundary.advance(minutes: 2)
    guard case .queued = try exactBoundary.service.produce(
        policy: exactBoundary.policy(),
        gamingStatus: exactBoundary.gamingStatus,
        baselineStatus: exactBoundary.baseline()
    ) else {
        Issue.record("Expected a 180-second-old observation to remain eligible")
        return
    }

    let beyondBoundary = try GamingPromptFixture()
    defer { beyondBoundary.remove() }
    try beyondBoundary.insertPriorityTask()
    try beyondBoundary.insertGaming(minutes: 10)
    beyondBoundary.clock.now = beyondBoundary.clock.now.addingTimeInterval(121)
    #expect(try beyondBoundary.service.produce(
        policy: beyondBoundary.policy(),
        gamingStatus: beyondBoundary.gamingStatus,
        baselineStatus: beyondBoundary.baseline()
    ) == .suppressed(.limitedCoverage))

    let futureDated = try GamingPromptFixture()
    defer { futureDated.remove() }
    try futureDated.insertPriorityTask()
    try futureDated.insertGaming(minutes: 10)
    futureDated.clock.now = futureDated.clock.now.addingTimeInterval(-120)
    #expect(try futureDated.service.produce(
        policy: futureDated.policy(),
        gamingStatus: futureDated.gamingStatus,
        baselineStatus: futureDated.baseline()
    ) == .suppressed(.limitedCoverage))
}

@Test
func invalidScreenwatchWithdrawalAloneAllowsSafeSameSessionRecovery() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability, dailyPromptCap: 1, promptCooldownMinutes: 35)
    guard case let .queued(original, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial gaming prompt")
        return
    }

    let limitedStatus = GamingStatus(
        budgetMinutes: fixture.gamingStatus.budgetMinutes,
        usedMinutes: fixture.gamingStatus.usedMinutes,
        unlockedRemainingMinutes: fixture.gamingStatus.unlockedRemainingMinutes,
        nextUnlockReason: fixture.gamingStatus.nextUnlockReason,
        confidenceIsLimited: true
    )
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: limitedStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.limitedCoverage))

    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restoredWithdrawal = try reopenedStore.episode(promptID: original.id)
    let withdrawn = try #require(restoredWithdrawal)
    #expect(withdrawn.state == .dismissed)
    #expect(withdrawn.resolutionOrigin == .system)
    #expect(withdrawn.resolutionReason == .screenwatchEvidenceInvalid)
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )

    guard case let .queued(recovered, wasInserted) = try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected fresh evidence to recover the same session without consuming cap or cooldown")
        return
    }
    #expect(wasInserted)
    #expect(recovered.id != original.id)
    #expect(recovered.decisionKey == original.decisionKey)
    #expect(try reopenedStore.unresolved().map(\.id) == [recovered.id])
}

@Test
func newestAmbiguousEvidenceWithdrawsStrongCoachingUntilCertainGamingReturns() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(
        level: .accountability,
        dailyPromptCap: 1,
        promptCooldownMinutes: 35
    )

    guard case let .queued(original, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected certain gaming evidence to queue the initial accountability prompt")
        return
    }
    #expect(try fixture.promptStore.unresolved().map(\.id) == [original.id])

    try fixture.insertLatestObservation(
        app: "Unclassified Browser",
        classification: .unknown,
        windowTitle: "Unclear local activity"
    )
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.limitedCoverage))
    #expect(try fixture.promptStore.unresolved().isEmpty)
    let storedWithdrawal = try fixture.promptStore.episode(promptID: original.id)
    let withdrawn = try #require(storedWithdrawal)
    #expect(withdrawn.state == .dismissed)
    #expect(withdrawn.resolutionOrigin == .system)
    #expect(withdrawn.resolutionReason == .screenwatchEvidenceInvalid)

    fixture.advance(minutes: 11)
    try fixture.insertGaming(minutes: 10)
    guard case let .queued(recovered, wasInserted) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected fresh certain gaming evidence to restore one normal prompt")
        return
    }
    #expect(wasInserted)
    #expect(recovered.id != original.id)
    #expect(try fixture.promptStore.unresolved().map(\.id) == [recovered.id])
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.sessionAlreadyHandled))
    #expect(try fixture.promptStore.unresolved().map(\.id) == [recovered.id])
}

@Test
func explicitUserDismissalStillEnforcesSessionDeduplicationCooldownAndDailyCap() throws {
    let sameSession = try GamingPromptFixture()
    defer { sameSession.remove() }
    try sameSession.insertPriorityTask()
    try sameSession.insertGaming(minutes: 10)
    let sameSessionPolicy = sameSession.policy(level: .accountability, dailyPromptCap: 6, promptCooldownMinutes: 35)
    guard case let .queued(original, _) = try sameSession.service.produce(
        policy: sameSessionPolicy,
        gamingStatus: sameSession.gamingStatus,
        baselineStatus: sameSession.baseline()
    ) else {
        Issue.record("Expected a prompt to dismiss explicitly")
        return
    }
    let dismissed = try sameSession.promptStore.dismiss(promptID: original.id)
    #expect(dismissed.resolutionOrigin == .user)
    #expect(dismissed.resolutionReason == .explicitDismissal)
    try sameSession.clearPromptResolutionMetadata(promptID: original.id)
    #expect(try sameSession.service.produce(
        policy: sameSessionPolicy,
        gamingStatus: sameSession.gamingStatus,
        baselineStatus: sameSession.baseline()
    ) == .suppressed(.sessionAlreadyHandled))

    sameSession.advance(minutes: 30)
    try sameSession.insertGaming(minutes: 10)
    #expect(try sameSession.service.produce(
        policy: sameSessionPolicy,
        gamingStatus: sameSession.gamingStatus,
        baselineStatus: sameSession.baseline()
    ) == .suppressed(.cooldownActive))

    let capped = try GamingPromptFixture()
    defer { capped.remove() }
    try capped.insertPriorityTask()
    try capped.insertGaming(minutes: 10)
    let cappedPolicy = capped.policy(level: .accountability, dailyPromptCap: 1, promptCooldownMinutes: 5)
    guard case let .queued(cappedOriginal, _) = try capped.service.produce(
        policy: cappedPolicy,
        gamingStatus: capped.gamingStatus,
        baselineStatus: capped.baseline()
    ) else {
        Issue.record("Expected a prompt that counts toward the daily cap")
        return
    }
    _ = try capped.promptStore.dismiss(promptID: cappedOriginal.id)
    capped.advance(minutes: 15)
    try capped.insertGaming(minutes: 10)
    #expect(try capped.service.produce(
        policy: cappedPolicy,
        gamingStatus: capped.gamingStatus,
        baselineStatus: capped.baseline()
    ) == .suppressed(.dailyLimitReached))
}

@Test
func gamingDriftUsesCorrectionsAndDoesNotRepeatTheSameSession() throws {
    let corrected = try GamingPromptFixture()
    defer { corrected.remove() }
    try corrected.insertPriorityTask()
    try corrected.insertGaming(minutes: 10)
    try corrected.correctCurrentSession(to: .work)
    #expect(try corrected.service.produce(
        policy: corrected.policy(), gamingStatus: corrected.gamingStatus, baselineStatus: corrected.baseline()
    ) == .suppressed(.noGamingSession))

    let deduped = try GamingPromptFixture()
    defer { deduped.remove() }
    try deduped.insertPriorityTask()
    try deduped.insertGaming(minutes: 10)
    guard case .queued = try deduped.service.produce(
        policy: deduped.policy(), gamingStatus: deduped.gamingStatus, baselineStatus: deduped.baseline()
    ) else {
        Issue.record("Expected first prompt")
        return
    }
    #expect(try deduped.service.produce(
        policy: deduped.policy(), gamingStatus: deduped.gamingStatus, baselineStatus: deduped.baseline()
    ) == .suppressed(.sessionAlreadyHandled))
    #expect(try deduped.promptStore.unresolved().count == 1)
}

@Test
func intentionalGamingOverrideRequiresTwoMinutesOfWorkBeforeEarlyReprompt() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial accountability prompt")
        return
    }

    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(
            promptID: episode.id,
            action: .continueIntentionally
        ),
        surface: .dashboard
    )
    let responses = try fixture.promptStore.responses(promptID: episode.id)
    #expect(responses.count == 1)
    #expect(responses[0].action == .continueIntentionally)
    #expect(responses[0].surface == .dashboard)
    #expect(try fixture.promptStore.unresolved().isEmpty)
    let behaviorCount = try fixture.behaviorRecordCount()
    #expect(try fixture.priorityTaskIsIncomplete())
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.intentionalOverrideActive))

    fixture.advance(minutes: 5)
    try fixture.insertWork(minutes: 1)
    fixture.advance(minutes: 11)
    try fixture.insertGaming(minutes: 10)
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.intentionalOverrideActive))

    fixture.advance(minutes: 5)
    try fixture.insertWork(minutes: 2)
    fixture.advance(minutes: 11)
    try fixture.insertGaming(minutes: 10)
    guard case let .queued(reprompt, wasInserted) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected normal coaching after two minutes of aligned work")
        return
    }
    #expect(wasInserted)
    #expect(reprompt.id != episode.id)
    #expect(try fixture.behaviorRecordCount() > behaviorCount)
    #expect(try fixture.priorityTaskIsIncomplete())
}

@Test
func intentionalGamingOverrideUsesConfiguredDurationAcrossRestart() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability, intentionalOverrideMinutes: 25)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial accountability prompt")
        return
    }
    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(
            promptID: episode.id,
            action: .continueIntentionally
        ),
        surface: .dashboard
    )

    fixture.advance(minutes: 20)
    try fixture.insertGaming(minutes: 10)
    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    #expect(try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.intentionalOverrideActive))

    fixture.advance(minutes: 6)
    try fixture.insertGaming(minutes: 6)
    guard case let .queued(reprompt, wasInserted) = try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected normal coaching after the override window")
        return
    }
    #expect(wasInserted)
    #expect(reprompt.id != episode.id)
    #expect(reprompt.actions.contains { $0.kind == .continueIntentionally })
    #expect(try fixture.priorityTaskIsIncomplete())
}

@Test
func resolvedGamingPromptStillDeduplicatesAndEnforcesCooldownAfterRestart() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the first accountability prompt")
        return
    }

    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .startWorkSprint,
        actionToken: PromptResponseToken.make(
            promptID: episode.id,
            action: .startWorkSprint
        ),
        surface: .dashboard
    )
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.sessionAlreadyHandled))

    fixture.advance(minutes: 30)
    try fixture.insertGaming(minutes: 10)
    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    #expect(try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.cooldownActive))
}

@Test
func fiveMoreMinutesSurvivesRestartAndProducesExactlyOneFollowUpAfterFiveMinutes() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .gentle, dailyPromptCap: 1, promptCooldownMinutes: 35)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial gentle prompt")
        return
    }
    #expect(episode.actions.contains { $0.kind == .fiveMoreMinutes && $0.title == "Five more minutes" })

    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .fiveMoreMinutes,
        actionToken: PromptResponseToken.make(promptID: episode.id, action: .fiveMoreMinutes),
        surface: .dashboard
    )
    fixture.advance(minutes: 4)
    try fixture.insertGaming(minutes: 4)
    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    #expect(try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.fiveMinuteSnoozeActive))

    fixture.advance(minutes: 1)
    try fixture.insertGaming(minutes: 1)
    guard case let .queued(followUp, wasInserted) = try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected one follow-up when the five-minute snooze ended")
        return
    }
    #expect(wasInserted)
    #expect(followUp.title == "Your five minutes are up")
    #expect(followUp.summary.contains("The five-minute extension has ended"))
    #expect(followUp.summary.contains("15 observed minutes in Steam"))
    #expect(followUp.payload["followUpForPromptID"] == episode.id)
    #expect(followUp.payload["snoozeDurationMinutes"] == "5")
    #expect(!followUp.actions.contains { $0.kind == .fiveMoreMinutes })
    #expect(followUp.actions.first?.kind == .returnToActiveTask)
    #expect(try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.sessionAlreadyHandled))
    #expect(try reopenedStore.unresolved().map(\.id) == [followUp.id])
}

@Test
func configuredCooldownAndDailyPromptLimitApplyAcrossSeparateSessions() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability, dailyPromptCap: 2, promptCooldownMinutes: 35)
    guard case .queued = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected first accountability prompt")
        return
    }

    fixture.advance(minutes: 30)
    try fixture.insertGaming(minutes: 10)
    #expect(try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.cooldownActive))

    fixture.advance(minutes: 6)
    try fixture.insertGaming(minutes: 6)
    guard case .queued = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected second accountability prompt after cooldown")
        return
    }
    fixture.advance(minutes: 36)
    try fixture.insertGaming(minutes: 10)
    let third = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    #expect(third == .suppressed(.dailyLimitReached), "Unexpected third result: \(third)")
    #expect(try fixture.quietDriftEpisodeCount() == 1)
    #expect(try fixture.quietDriftObservedMinutes() == 10)
    fixture.advance(minutes: 1)
    try fixture.insertGaming(minutes: 1)
    #expect(try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.dailyLimitReached))
    #expect(try fixture.quietDriftEpisodeCount() == 1)
    #expect(try fixture.quietDriftObservedMinutes() == 11)
    #expect(try fixture.promptStore.unresolved().isEmpty)
}

@Test
func gamingObservationModeNeverProducesABehaviorPrompt() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let result = try fixture.service.produce(
        policy: fixture.policy(budgetEnabled: false),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    )
    #expect(result == .suppressed(.gamingBudgetDisabled))
    #expect(try fixture.promptStore.unresolved().isEmpty)
}

@Test
func planningAndSourcePromptsDoNotConsumeTheBehaviorInterventionCap() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    for index in 0..<8 {
        _ = try fixture.promptStore.enqueue(PromptDraft(
            decisionKey: "non-behavior-\(index)",
            type: index.isMultiple(of: 2) ? "PLAN_READY" : "SOURCE_WARNING",
            title: "Planning or source update",
            summary: "This prompt is not a behavior intervention.",
            actions: [PromptAction(kind: .acceptPlan, title: "Review")]
        ))
    }
    try fixture.insertGaming(minutes: 10)

    guard case .queued = try fixture.service.produce(
        policy: fixture.policy(level: .gentle, dailyPromptCap: 1, promptCooldownMinutes: 5),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected a behavior prompt despite unrelated planning and source prompts")
        return
    }
}

@Test
func gentleResponsePausesNewBehaviorInterventionsForExactlyFifteenMinutes() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .gentle, dailyPromptCap: 6, promptCooldownMinutes: 5)
    guard case let .queued(first, _) = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial gentle prompt")
        return
    }
    _ = try fixture.promptStore.respond(
        promptID: first.id,
        action: .returnToActiveTask,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .returnToActiveTask),
        surface: .dashboard
    )

    fixture.advance(minutes: 14)
    try fixture.insertGaming(minutes: 10)
    let beforeGentleBoundary = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    #expect(beforeGentleBoundary == .suppressed(.responsePauseActive), "Unexpected result: \(beforeGentleBoundary)")

    fixture.advance(minutes: 1)
    let afterGentleBoundary = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    guard case .queued = afterGentleBoundary else {
        Issue.record("Expected a new gentle prompt after the exact fifteen-minute pause, got \(afterGentleBoundary)")
        return
    }
}

@Test
func accountabilityResponsePausesNewBehaviorInterventionsForExactlyTwentyMinutes() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability, dailyPromptCap: 6, promptCooldownMinutes: 5)
    guard case let .queued(first, _) = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial accountability prompt")
        return
    }
    _ = try fixture.promptStore.respond(
        promptID: first.id,
        action: .startWorkSprint,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .startWorkSprint),
        surface: .dashboard
    )

    fixture.advance(minutes: 19)
    try fixture.insertGaming(minutes: 10)
    let beforeAccountabilityBoundary = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    #expect(beforeAccountabilityBoundary == .suppressed(.responsePauseActive), "Unexpected result: \(beforeAccountabilityBoundary)")

    fixture.advance(minutes: 1)
    let afterAccountabilityBoundary = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    guard case .queued = afterAccountabilityBoundary else {
        Issue.record("Expected a new accountability prompt after the exact twenty-minute pause, got \(afterAccountabilityBoundary)")
        return
    }
}

@Test
func fiveMinuteFollowUpOffersEndDayAndSuppressesFurtherPromptsAfterSelection() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .gentle, dailyPromptCap: 6, promptCooldownMinutes: 5)
    guard case let .queued(first, _) = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial gentle prompt")
        return
    }
    _ = try fixture.promptStore.respond(
        promptID: first.id,
        action: .fiveMoreMinutes,
        actionToken: PromptResponseToken.make(promptID: first.id, action: .fiveMoreMinutes),
        surface: .dashboard
    )

    fixture.advance(minutes: 5)
    try fixture.insertGaming(minutes: 5)
    guard case let .queued(followUp, _) = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the five-minute follow-up")
        return
    }
    #expect(followUp.actions.contains { $0.kind == .endWorkday && $0.title == "I am done today" })
    #expect(followUp.actions.filter { $0.role == .secondary }.count <= 3)
    _ = try fixture.promptStore.respond(
        promptID: followUp.id,
        action: .endWorkday,
        actionToken: PromptResponseToken.make(promptID: followUp.id, action: .endWorkday),
        surface: .dashboard
    )

    fixture.advance(minutes: 60)
    try fixture.insertGaming(minutes: 10)
    #expect(try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.workdayClosed))
}

@Test
func legacyGamingPolicyDefaultsToGentleCoaching() throws {
    let data = Data(#"{"version":1,"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15}"#.utf8)
    let decoded = try JSONDecoder().decode(GamingPolicy.self, from: data)
    #expect(decoded.coachingLevel == .gentle)
    #expect(decoded.intentionalOverrideMinutes == 45)
    #expect(decoded.dailyPromptCap == 1)
    #expect(decoded.promptCooldownMinutes == 180)

    let legacyAccountability = try JSONDecoder().decode(
        GamingPolicy.self,
        from: Data(#"{"version":1,"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15,"coachingLevel":"accountability"}"#.utf8)
    )
    #expect(legacyAccountability.dailyPromptCap == 3)
    #expect(legacyAccountability.promptCooldownMinutes == 60)

    let clampedMinimum = GamingPolicy(intentionalOverrideMinutes: 0)
    #expect(clampedMinimum.intentionalOverrideMinutes == 5)

    let excessive = UserPolicy.defaults(timeZoneIdentifier: "UTC").replacingGamingPolicy(
        GamingPolicy(intentionalOverrideMinutes: 1_441)
    )
    #expect(excessive.validationViolations().contains {
        $0.field == "gaming.intentionalOverrideMinutes"
    })
}

@Test
func newTaskAndIdleReturnReceiveExplicitGraceWhileSustainedGamingBypassesIt() throws {
    let newTask = try GamingPromptFixture()
    defer { newTask.remove() }
    try newTask.insertPriorityTask()
    try newTask.insertGaming(minutes: 2)
    try newTask.startTask(secondsAgo: 150)
    #expect(try newTask.service.produce(
        policy: newTask.policy(level: .accountability),
        gamingStatus: newTask.gamingStatus,
        baselineStatus: newTask.baseline()
    ) == .suppressed(.taskStartGrace))

    let idleReturn = try GamingPromptFixture()
    defer { idleReturn.remove() }
    try idleReturn.insertPriorityTask()
    try idleReturn.startTask(secondsAgo: 600)
    try idleReturn.insertIdleThenGaming()
    #expect(try idleReturn.service.produce(
        policy: idleReturn.policy(level: .accountability),
        gamingStatus: idleReturn.gamingStatus,
        baselineStatus: idleReturn.baseline()
    ) == .suppressed(.returnFromIdleGrace))

    let sustained = try GamingPromptFixture()
    defer { sustained.remove() }
    try sustained.insertPriorityTask()
    try sustained.insertGaming(minutes: 10)
    try sustained.startTask(secondsAgo: 90)
    guard case .queued = try sustained.service.produce(
        policy: sustained.policy(level: .accountability),
        gamingStatus: sustained.gamingStatus,
        baselineStatus: sustained.baseline()
    ) else {
        Issue.record("Expected sustained high-confidence gaming to bypass task-start grace")
        return
    }
}

@Test
func savedGraceDurationsAffectTheNextDecisionWithoutRestart() throws {
    let taskGrace = try GamingPromptFixture()
    defer { taskGrace.remove() }
    try taskGrace.insertPriorityTask()
    try taskGrace.startTask(secondsAgo: 12 * 60)
    try taskGrace.insertGaming(minutes: 10)

    #expect(try taskGrace.service.produce(
        policy: taskGrace.policy(level: .accountability, taskStartGraceMinutes: 15),
        gamingStatus: taskGrace.gamingStatus,
        baselineStatus: taskGrace.baseline()
    ) == .suppressed(.taskStartGrace))

    guard case .queued = try taskGrace.service.produce(
        policy: taskGrace.policy(level: .accountability, taskStartGraceMinutes: 10),
        gamingStatus: taskGrace.gamingStatus,
        baselineStatus: taskGrace.baseline()
    ) else {
        Issue.record("Expected the next evaluation to use the shorter saved task-start grace")
        return
    }

    let idleGrace = try GamingPromptFixture()
    defer { idleGrace.remove() }
    try idleGrace.insertPriorityTask()
    try idleGrace.startTask(secondsAgo: 10 * 60)
    try idleGrace.insertIdleThenGaming()

    #expect(try idleGrace.service.produce(
        policy: idleGrace.policy(level: .accountability, returnFromIdleGraceMinutes: 2),
        gamingStatus: idleGrace.gamingStatus,
        baselineStatus: idleGrace.baseline()
    ) == .suppressed(.returnFromIdleGrace))

    #expect(try idleGrace.service.produce(
        policy: idleGrace.policy(level: .accountability, returnFromIdleGraceMinutes: 0),
        gamingStatus: idleGrace.gamingStatus,
        baselineStatus: idleGrace.baseline()
    ) == .suppressed(.belowThreshold))
}

@Test
func neutralSupportingActivitySuppressesCoachingWithoutMutatingTheActiveTask() throws {
    for neutralApp in ["System Settings", "1Password", "Finder Downloads", "Slack"] {
        let fixture = try GamingPromptFixture()
        defer { fixture.remove() }
        try fixture.insertPriorityTask()
        try fixture.startTask(secondsAgo: 900)
        try fixture.insertGaming(minutes: 10)
        try fixture.insertLatestObservation(app: neutralApp, classification: .unknown)

        #expect(try fixture.service.produce(
            policy: fixture.policy(level: .accountability),
            gamingStatus: fixture.gamingStatus,
            baselineStatus: fixture.baseline()
        ) == .suppressed(.neutralSupportingActivity))
        #expect(try fixture.activeTaskCount() == 1)
        #expect(try fixture.promptStore.unresolved().isEmpty)
    }

    for nonNeutral in [
        (app: "OpenTTD", title: "", url: ""),
        (app: "Steam", title: "Open World", url: ""),
        (app: "Gmail Notifier", title: "Inbox", url: "")
    ] {
        let fixture = try GamingPromptFixture()
        defer { fixture.remove() }
        try fixture.insertPriorityTask()
        try fixture.startTask(secondsAgo: 900)
        try fixture.insertGaming(minutes: 10)
        try fixture.insertLatestObservation(
            app: nonNeutral.app,
            classification: .gaming,
            windowTitle: nonNeutral.title,
            url: nonNeutral.url
        )

        guard case .queued = try fixture.service.produce(
            policy: fixture.policy(level: .accountability),
            gamingStatus: fixture.gamingStatus,
            baselineStatus: fixture.baseline()
        ) else {
            Issue.record("Expected \(nonNeutral.app) / \(nonNeutral.title) to remain non-neutral")
            continue
        }
        #expect(try fixture.activeTaskCount() == 1)
    }
}

private final class GamingPromptFixture: @unchecked Sendable {
    final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    let databaseURL: URL
    let clock: Clock
    let promptStore: PromptInboxStore
    let service: GamingDriftPromptService
    let gamingStatus = GamingStatus(
        budgetMinutes: 0,
        usedMinutes: 10,
        unlockedRemainingMinutes: 0,
        nextUnlockReason: "Finish priority work",
        confidenceIsLimited: false
    )

    init() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaming-prompt-\(UUID().uuidString).sqlite")
        clock = Clock(try #require(ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z")))
        promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { [clock] in clock.now })
        service = try GamingDriftPromptService(
            databaseURL: databaseURL,
            promptStore: promptStore,
            now: { [clock] in clock.now }
        )
    }

    func remove() { try? FileManager.default.removeItem(at: databaseURL) }

    func advance(minutes: Int) {
        clock.now = clock.now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func baseline(completeDays: Int = 7) -> BaselineObservationStatus {
        BaselineObservationStatus(
            days: (0..<completeDays).map { offset in
                BaselineObservationDay(
                    localDay: String(format: "2026-07-%02d", offset + 1),
                    observedMinutes: 60,
                    workMinutes: 45,
                    gamingMinutes: 10,
                    distractingMinutes: 0,
                    unknownMinutes: 5,
                    eligibleDriftCount: 0,
                    coverage: .complete,
                    recordedAt: clock.now
                )
            },
            report: BaselineObservationReport(
                averageObservedWorkMinutes: 45,
                gamingDayCount: completeDays,
                totalGamingMinutes: completeDays * 10,
                eligibleDriftCount: 0,
                unknownSharePercent: 8
            )
        )
    }

    func policy(
        paused: Bool = false,
        workStart: LocalTime = LocalTime(hour: 8, minute: 0),
        level: CoachingLevel = .gentle,
        intentionalOverrideMinutes: Int = 45,
        dailyPromptCap: Int? = nil,
        promptCooldownMinutes: Int? = nil,
        taskStartGraceMinutes: Int = 3,
        returnFromIdleGraceMinutes: Int = 1,
        budgetEnabled: Bool = true
    ) -> UserPolicy {
        let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        return UserPolicy(
            operatingMode: .suggest,
            automationPause: paused ? .pausedIndefinitely : .running,
            schedule: SchedulePolicy(
                timeZoneIdentifier: "UTC",
                workWindows: [WeeklyWorkWindow(
                    weekdays: Weekday.allCases,
                    start: workStart,
                    end: LocalTime(hour: 18, minute: 0)
                )],
                quietHours: defaults.schedule.quietHours,
                nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
                morningConfirmationTime: defaults.schedule.morningConfirmationTime,
                planningCapacityPercent: defaults.schedule.planningCapacityPercent
            ),
            calendar: defaults.calendar,
            privacy: defaults.privacy,
            wake: defaults.wake,
            behavior: defaults.behavior,
            capture: defaults.capture,
            gaming: GamingPolicy(
                dailyBudgetMinutes: 0,
                priorityTaskRewardMinutes: 0,
                coachingLevel: level,
                intentionalOverrideMinutes: intentionalOverrideMinutes,
                dailyPromptCap: dailyPromptCap,
                promptCooldownMinutes: promptCooldownMinutes,
                taskStartGraceMinutes: taskStartGraceMinutes,
                returnFromIdleGraceMinutes: returnFromIdleGraceMinutes,
                budgetEnabled: budgetEnabled
            ),
            reminderLists: defaults.reminderLists
        )
    }

    func insertPriorityTask() throws {
        try execute("INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES ('priority-1', 'Ship client proposal', 9, 0, '2026-07-13T09:00:00Z', 'local');")
        try execute("INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional) VALUES ('2026-07-13', 'priority-1', 1, 1, 60, '2026-07-13T09:00:00Z', 'main objective', 100, 0);")
    }

    func insertGaming(minutes: Int) throws {
        let end = Int64(clock.now.timeIntervalSince1970) - 60
        for offset in 0..<minutes {
            let epoch = end - Int64((minutes - 1 - offset) * 60)
            try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(epoch), '09-00-00', 'Steam', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'gaming', 1);")
        }
    }

    func startTask(secondsAgo: TimeInterval) throws {
        let store = try TaskExecutionStore(databaseURL: databaseURL)
        try store.apply(.start, taskID: "priority-1", at: clock.now.addingTimeInterval(-secondsAgo))
    }

    func insertIdleThenGaming() throws {
        let now = Int64(clock.now.timeIntervalSince1970)
        try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(now - 120), '09-58-00', '', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'idle', 1);")
        try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(now - 30), '09-59-30', 'Steam', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'gaming', 1);")
    }

    func insertLatestObservation(
        app: String,
        classification: BehaviorClassification,
        windowTitle: String = "",
        url: String = ""
    ) throws {
        let epoch = Int64(clock.now.timeIntervalSince1970) - 30
        let safeApp = app.replacingOccurrences(of: "'", with: "''")
        let safeTitle = windowTitle.replacingOccurrences(of: "'", with: "''")
        let safeURL = url.replacingOccurrences(of: "'", with: "''")
        try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(epoch), '09-59-30', '\(safeApp)', '\(safeTitle)', '\(safeURL)', 0, NULL, '2026-07-13T10:00:00Z', '\(classification.rawValue)', 1);")
    }

    func activeTaskCount() throws -> Int {
        try scalar("SELECT COUNT(*) FROM task_execution_states WHERE state = 'active';")
    }

    func insertWork(minutes: Int) throws {
        let end = Int64(clock.now.timeIntervalSince1970) - 60
        for offset in 0..<minutes {
            let epoch = end - Int64((minutes - 1 - offset) * 60)
            try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(epoch), '09-00-00', 'Xcode', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'work', 1);")
        }
    }

    func behaviorRecordCount() throws -> Int {
        try scalar("SELECT COUNT(*) FROM behavior_records;")
    }

    func quietDriftEpisodeCount() throws -> Int {
        try scalar("SELECT COUNT(*) FROM quiet_drift_episodes;")
    }

    func quietDriftObservedMinutes() throws -> Int {
        try scalar("SELECT COALESCE(MAX(observed_minutes), 0) FROM quiet_drift_episodes;")
    }

    func clearPromptResolutionMetadata(promptID: String) throws {
        let safePromptID = promptID.replacingOccurrences(of: "'", with: "''")
        try execute("UPDATE prompt_episodes SET resolution_origin = NULL, resolution_reason = NULL WHERE id = '\(safePromptID)';")
    }

    func priorityTaskIsIncomplete() throws -> Bool {
        try scalar("SELECT COUNT(*) FROM source_tasks WHERE source_id = 'priority-1' AND is_completed = 0;") == 1
    }

    func correctCurrentSession(to classification: BehaviorClassification) throws {
        let end = Int64(clock.now.timeIntervalSince1970)
        let start = end - 10 * 60
        try execute("INSERT INTO daily_review_corrections(source_day, start_epoch, end_epoch, classification, created_at_utc) VALUES ('2026-07-13', \(start), \(end), '\(classification.rawValue)', '2026-07-13T10:00:00Z');")
    }

    func insertOpenPause(_ reason: TaskPauseReason) throws {
        try execute("INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES ('priority-1', '\(reason.rawValue)', '2026-07-13T09:55:00Z', NULL);")
    }

    func closePauses() throws {
        try execute("UPDATE task_pause_events SET resumed_at = '2026-07-13T09:56:00Z' WHERE resumed_at IS NULL;")
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw GamingDriftPromptServiceError.openDatabase
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw GamingDriftPromptServiceError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func scalar(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw GamingDriftPromptServiceError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw GamingDriftPromptServiceError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw GamingDriftPromptServiceError.database(String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
