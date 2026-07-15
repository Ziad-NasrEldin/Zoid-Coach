import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func crossedInactivePlanningBoundaryRecoversOneInvitation() async throws {
    let service = MissedPlanningInvitationRecoveryService()
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let calendar = recoveryCalendar(timeZone: timeZone)
    let inactiveAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 15,
        hour: 21,
        minute: 55
    ))!
    let startupAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 15,
        hour: 22,
        minute: 10
    ))!

    let result = try await service.recover(
        request: MissedPlanningInvitationRecoveryRequest(
            previousHeartbeat: inactiveAt,
            startupAt: startupAt,
            timeZoneIdentifier: timeZone.identifier,
            planningTime: LocalTime(hour: 22, minute: 0),
            lastRecoveredLocalDay: nil,
            lastRecoveredTimeZoneIdentifier: nil
        ),
        preparePlan: { _ in .drafted(itemCount: 3) },
        enqueueInvitation: { day, itemCount, timeZoneIdentifier in
            PromptEpisode(
                id: "invitation-1",
                decisionKey: "plan-ready:2026-07-16",
                type: "PLAN_READY",
                state: .queued,
                title: "Your plan is ready",
                summary: "3 commitments are ready to review.",
                actions: [PromptAction(kind: .reviewPlan, title: "Review", role: .primary)],
                payload: [
                    "localDay": recoveryLocalDay(day, timeZoneIdentifier: timeZoneIdentifier),
                    "itemCount": String(itemCount),
                ],
                createdAt: startupAt,
                expiresAt: startupAt.addingTimeInterval(86_400)
            )
        },
        persistCheckpoint: { _, _, _, _ in }
    )

    guard case let .recovered(recovery) = result else {
        Issue.record("Expected a recovered planning invitation")
        return
    }
    #expect(recovery.targetLocalDay == "2026-07-16")
    #expect(recovery.planDisposition == .drafted)
    #expect(recovery.itemCount == 3)
    #expect(recovery.notificationEpisode.id == "invitation-1")
}

@Test
func startupBeforePlanningBoundaryDoesNotPrepareOrInvite() async throws {
    let service = MissedPlanningInvitationRecoveryService()
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let calendar = recoveryCalendar(timeZone: timeZone)
    let calls = RecoveryCallRecorder()
    let inactiveAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 15,
        hour: 20,
        minute: 0
    ))!
    let startupAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 15,
        hour: 21,
        minute: 59
    ))!

    let result = try await service.recover(
        request: MissedPlanningInvitationRecoveryRequest(
            previousHeartbeat: inactiveAt,
            startupAt: startupAt,
            timeZoneIdentifier: timeZone.identifier,
            planningTime: LocalTime(hour: 22, minute: 0),
            lastRecoveredLocalDay: "2026-07-14",
            lastRecoveredTimeZoneIdentifier: timeZone.identifier
        ),
        preparePlan: { _ in
            calls.recordPreparation()
            return .drafted(itemCount: 1)
        },
        enqueueInvitation: { _, _, _ in
            calls.recordInvitation()
            return recoveryEpisode(id: "unexpected", createdAt: startupAt)
        },
        persistCheckpoint: { _, _, _, _ in calls.recordCheckpoint() }
    )

    #expect(result == .notRequired)
    #expect(calls.snapshot == .init(preparations: 0, invitations: 0, checkpoints: 0))
}

@Test
func configuredTimeZoneOwnsTheRecoveredTargetDay() async throws {
    let timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
    let calendar = recoveryCalendar(timeZone: timeZone)
    let inactiveAt = calendar.date(from: DateComponents(
        year: 2026, month: 7, day: 16, hour: 21, minute: 50
    ))!
    let startupAt = calendar.date(from: DateComponents(
        year: 2026, month: 7, day: 16, hour: 22, minute: 5
    ))!

    let result = try await recoveryServiceResult(
        previousHeartbeat: inactiveAt,
        startupAt: startupAt,
        timeZone: timeZone,
        preparation: .drafted(itemCount: 2)
    )

    guard case let .recovered(recovery) = result else {
        Issue.record("Expected recovery in the configured local time zone")
        return
    }
    #expect(recovery.targetLocalDay == "2026-07-17")
    #expect(recoveryLocalDay(
        recovery.targetDay,
        timeZoneIdentifier: timeZone.identifier
    ) == "2026-07-17")
}

@Test
func existingValidPlanIsRetainedAndInvitedWithoutRedrafting() async throws {
    let fixture = standardRecoveryFixture()
    let result = try await recoveryServiceResult(
        previousHeartbeat: fixture.inactiveAt,
        startupAt: fixture.startupAt,
        timeZone: fixture.timeZone,
        preparation: .retainedExisting(itemCount: 4)
    )

    guard case let .recovered(recovery) = result else {
        Issue.record("Expected the existing plan to be invited")
        return
    }
    #expect(recovery.planDisposition == .retainedExisting)
    #expect(recovery.itemCount == 4)
    #expect(recovery.notificationEpisode.payload["itemCount"] == "4")
}

@Test
func persistedRecoveryCheckpointMakesRepeatStartupIdempotent() async throws {
    let service = MissedPlanningInvitationRecoveryService()
    let fixture = standardRecoveryFixture()
    let calls = RecoveryCallRecorder()
    let result = try await service.recover(
        request: MissedPlanningInvitationRecoveryRequest(
            previousHeartbeat: fixture.inactiveAt,
            startupAt: fixture.startupAt,
            timeZoneIdentifier: fixture.timeZone.identifier,
            planningTime: LocalTime(hour: 22, minute: 0),
            lastRecoveredLocalDay: "2026-07-16",
            lastRecoveredTimeZoneIdentifier: fixture.timeZone.identifier
        ),
        preparePlan: { _ in
            calls.recordPreparation()
            return .drafted(itemCount: 2)
        },
        enqueueInvitation: { _, _, _ in
            calls.recordInvitation()
            return recoveryEpisode(id: "unexpected", createdAt: fixture.startupAt)
        },
        persistCheckpoint: { _, _, _, _ in calls.recordCheckpoint() }
    )

    #expect(result == .alreadyRecovered(targetLocalDay: "2026-07-16"))
    #expect(calls.snapshot == .init(preparations: 0, invitations: 0, checkpoints: 0))
}

@Test
func checkpointFailureRetriesWithoutDuplicatingTheInvitation() async throws {
    let service = MissedPlanningInvitationRecoveryService()
    let fixture = standardRecoveryFixture()
    let databaseURL = recoveryDatabaseURL("checkpoint-retry")
    defer { removeRecoveryDatabase(databaseURL) }
    let store = try PromptInboxStore(
        databaseURL: databaseURL,
        now: { fixture.startupAt },
        makeID: { "stable-invitation" }
    )
    let checkpoint = FailingRecoveryCheckpoint()
    let request = MissedPlanningInvitationRecoveryRequest(
        previousHeartbeat: fixture.inactiveAt,
        startupAt: fixture.startupAt,
        timeZoneIdentifier: fixture.timeZone.identifier,
        planningTime: LocalTime(hour: 22, minute: 0),
        lastRecoveredLocalDay: nil,
        lastRecoveredTimeZoneIdentifier: nil
    )
    let enqueue: @Sendable (Date, Int, String) throws -> PromptEpisode = { day, itemCount, zone in
        try store.enqueue(PlanningInvitationPolicy.promptDraft(
            localDay: recoveryLocalDay(day, timeZoneIdentifier: zone),
            itemCount: itemCount,
            expiresAt: fixture.startupAt.addingTimeInterval(86_400)
        )).episode
    }

    await #expect(throws: RecoveryTestError.checkpointWrite) {
        _ = try await service.recover(
            request: request,
            preparePlan: { _ in .drafted(itemCount: 2) },
            enqueueInvitation: enqueue,
            persistCheckpoint: { _, _, _, _ in try checkpoint.persist() }
        )
    }
    let retried = try await service.recover(
        request: request,
        preparePlan: { _ in .drafted(itemCount: 2) },
        enqueueInvitation: enqueue,
        persistCheckpoint: { _, _, _, _ in try checkpoint.persist() }
    )

    guard case let .recovered(recovery) = retried else {
        Issue.record("Expected the partial recovery to retry")
        return
    }
    #expect(recovery.notificationEpisode.id == "stable-invitation")
    #expect(try store.unresolved().map(\.id) == ["stable-invitation"])
    #expect(checkpoint.successCount == 1)
}

@Test
func recoveryReturnsOnlyThePrivacySafeNotificationThatIsDue() async throws {
    let fixture = standardRecoveryFixture()
    let privateTaskTitle = "Acquire confidential company"
    let service = MissedPlanningInvitationRecoveryService()
    let result = try await service.recover(
        request: MissedPlanningInvitationRecoveryRequest(
            previousHeartbeat: fixture.inactiveAt,
            startupAt: fixture.startupAt,
            timeZoneIdentifier: fixture.timeZone.identifier,
            planningTime: LocalTime(hour: 22, minute: 0),
            lastRecoveredLocalDay: nil,
            lastRecoveredTimeZoneIdentifier: nil
        ),
        preparePlan: { _ in .drafted(itemCount: 1) },
        enqueueInvitation: { day, itemCount, zone in
            let draft = PlanningInvitationPolicy.promptDraft(
                localDay: recoveryLocalDay(day, timeZoneIdentifier: zone),
                itemCount: itemCount,
                expiresAt: fixture.startupAt.addingTimeInterval(86_400)
            )
            return PromptEpisode(
                id: "privacy-safe",
                decisionKey: draft.decisionKey,
                type: draft.type,
                state: .queued,
                title: draft.title,
                summary: draft.summary,
                actions: draft.actions,
                payload: draft.payload,
                createdAt: fixture.startupAt,
                expiresAt: draft.expiresAt
            )
        },
        persistCheckpoint: { _, _, _, _ in }
    )

    guard case let .recovered(recovery) = result else {
        Issue.record("Expected a notification-due result")
        return
    }
    let exposedText = ([
        recovery.notificationEpisode.title,
        recovery.notificationEpisode.summary,
    ] + recovery.notificationEpisode.payload.flatMap { [$0.key, $0.value] })
        .joined(separator: " ")
    #expect(exposedText.contains(privateTaskTitle) == false)
    #expect(recovery.notificationEpisode.payload == [
        "allowsDismissal": "true",
        "itemCount": "1",
        "localDay": "2026-07-16",
    ])
}

private func recoveryCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func recoveryLocalDay(_ date: Date, timeZoneIdentifier: String) -> String {
    let timeZone = TimeZone(identifier: timeZoneIdentifier)!
    let components = recoveryCalendar(timeZone: timeZone).dateComponents(
        [.year, .month, .day],
        from: date
    )
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
}

private func recoveryEpisode(id: String, createdAt: Date) -> PromptEpisode {
    PromptEpisode(
        id: id,
        decisionKey: "plan-ready:2026-07-16",
        type: "PLAN_READY",
        state: .queued,
        title: "Your plan is ready",
        summary: "1 commitment is ready to review.",
        actions: [PromptAction(kind: .reviewPlan, title: "Review", role: .primary)],
        payload: ["localDay": "2026-07-16", "itemCount": "1"],
        createdAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(86_400)
    )
}

private func recoveryServiceResult(
    previousHeartbeat: Date,
    startupAt: Date,
    timeZone: TimeZone,
    preparation: MissedPlanningPlanPreparation
) async throws -> MissedPlanningInvitationRecoveryResult {
    try await MissedPlanningInvitationRecoveryService().recover(
        request: MissedPlanningInvitationRecoveryRequest(
            previousHeartbeat: previousHeartbeat,
            startupAt: startupAt,
            timeZoneIdentifier: timeZone.identifier,
            planningTime: LocalTime(hour: 22, minute: 0),
            lastRecoveredLocalDay: nil,
            lastRecoveredTimeZoneIdentifier: nil
        ),
        preparePlan: { _ in preparation },
        enqueueInvitation: { day, itemCount, zone in
            var episode = recoveryEpisode(id: "invitation", createdAt: startupAt)
            episode = PromptEpisode(
                id: episode.id,
                decisionKey: "plan-ready:\(recoveryLocalDay(day, timeZoneIdentifier: zone))",
                type: episode.type,
                state: episode.state,
                title: episode.title,
                summary: episode.summary,
                actions: episode.actions,
                payload: [
                    "localDay": recoveryLocalDay(day, timeZoneIdentifier: zone),
                    "itemCount": String(itemCount),
                ],
                createdAt: episode.createdAt,
                expiresAt: episode.expiresAt
            )
            return episode
        },
        persistCheckpoint: { _, _, _, _ in }
    )
}

private func standardRecoveryFixture() -> (timeZone: TimeZone, inactiveAt: Date, startupAt: Date) {
    let timeZone = TimeZone(identifier: "Africa/Cairo")!
    let calendar = recoveryCalendar(timeZone: timeZone)
    return (
        timeZone,
        calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 15, hour: 21, minute: 55
        ))!,
        calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 15, hour: 22, minute: 10
        ))!
    )
}

private enum RecoveryTestError: Error {
    case checkpointWrite
}

private final class FailingRecoveryCheckpoint: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var successCount: Int { lock.withLock { max(0, attempts - 1) } }

    func persist() throws {
        try lock.withLock {
            attempts += 1
            if attempts == 1 { throw RecoveryTestError.checkpointWrite }
        }
    }
}

private func recoveryDatabaseURL(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-missed-planning-\(suffix)-\(UUID().uuidString).sqlite")
}

private func removeRecoveryDatabase(_ url: URL) {
    for suffix in ["", "-shm", "-wal"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private final class RecoveryCallRecorder: @unchecked Sendable {
    struct Snapshot: Equatable {
        let preparations: Int
        let invitations: Int
        let checkpoints: Int
    }

    private let lock = NSLock()
    private var preparations = 0
    private var invitations = 0
    private var checkpoints = 0

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                preparations: preparations,
                invitations: invitations,
                checkpoints: checkpoints
            )
        }
    }

    func recordPreparation() { lock.withLock { preparations += 1 } }
    func recordInvitation() { lock.withLock { invitations += 1 } }
    func recordCheckpoint() { lock.withLock { checkpoints += 1 } }
}
