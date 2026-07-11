import Foundation
import ZoidCoachCore

public final class VoiceAgentController: @unchecked Sendable {
    private let persistence: VoicePersistenceStore
    private let toolRouter: VoiceToolRouter
    private let snapshot: @Sendable () throws -> TodaySnapshot
    private let policy: @Sendable () throws -> UserPolicy
    private let activeCodexJobs: @Sendable () async throws -> [CodexJob]
    private let upcomingCommitments: @Sendable () async throws -> [CalendarCommitment]
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        persistence: VoicePersistenceStore,
        toolRouter: VoiceToolRouter,
        snapshot: @escaping @Sendable () throws -> TodaySnapshot,
        policy: @escaping @Sendable () throws -> UserPolicy,
        activeCodexJobs: @escaping @Sendable () async throws -> [CodexJob],
        upcomingCommitments: @escaping @Sendable () async throws -> [CalendarCommitment],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.toolRouter = toolRouter
        self.snapshot = snapshot
        self.policy = policy
        self.activeCodexJobs = activeCodexJobs
        self.upcomingCommitments = upcomingCommitments
        self.now = now
    }

    public func context() async throws -> ChiefOfStaffContextPacket {
        let currentPolicy = try policy()
        let date = now()
        return ChiefOfStaffContextPacket(
            generatedAt: date,
            snapshot: try snapshot(),
            memories: try persistence.activeMemoryFacts(at: date),
            activeCodexJobs: try await activeCodexJobs(),
            upcomingCommitments: try await upcomingCommitments(),
            operatingMode: currentPolicy.operatingMode,
            automationIsPaused: currentPolicy.automationPause.isPaused,
            schedule: currentPolicy.schedule
        )
    }

    public func invoke(_ invocation: VoiceToolInvocation) async -> VoiceToolExecutionResult {
        await toolRouter.handle(invocation)
    }

    public func resolveApproval(id: String, approved: Bool) async -> VoiceToolExecutionResult {
        await toolRouter.resolveApproval(id: id, approved: approved)
    }

    public func save(_ session: VoiceSession) throws { try persistence.save(session) }

    public func append(_ turn: ConversationTurn) throws { try persistence.append(turn) }

    public func recordTransmission(_ selection: ScreenContextSelection, sessionID: String) throws {
        guard selection.mayTransmitPrivateContent else { return }
        try persistence.recordTransmission(selection, sessionID: sessionID, transmittedAt: now())
    }

    public func pruneExpiredTranscripts() throws {
        try persistence.pruneTranscripts(olderThan: now().addingTimeInterval(-30 * 86_400))
    }

    public func usage() throws -> VoiceUsageLedger {
        try lock.withLock {
            let currentPolicy = try policy()
            let timeZone = TimeZone(identifier: currentPolicy.schedule.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = now()
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
            guard let stored = try persistence.latestUsageLedger() else {
                return VoiceUsageLedger(periodStart: monthStart)
            }
            return stored.recording(
                VoiceUsageSample(inputAudioSeconds: 0, outputAudioSeconds: 0),
                at: date,
                calendar: calendar,
                timeZone: timeZone
            )
        }
    }

    public func record(_ sample: VoiceUsageSample) throws -> VoiceUsageLedger {
        try lock.withLock {
            let currentPolicy = try policy()
            let timeZone = TimeZone(identifier: currentPolicy.schedule.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = now()
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
            let current = try persistence.latestUsageLedger() ?? VoiceUsageLedger(periodStart: monthStart)
            let updated = current.recording(sample, at: date, calendar: calendar, timeZone: timeZone)
            try persistence.save(updated, updatedAt: date)
            return updated
        }
    }

    public func reserveCloudSession() throws -> VoiceBudgetReservation {
        try lock.withLock {
            let current = try currentUsageLedger()
            let id = UUID().uuidString
            guard let reserved = current.reserving(
                id: id,
                maximumUSDMicros: VoiceUsageLedger.hardMonthlyLimitUSDMicros
            ) else {
                throw VoiceBudgetError.capReached
            }
            try persistence.save(reserved, updatedAt: now())
            return VoiceBudgetReservation(id: id, ledger: reserved)
        }
    }

    public func settleCloudSession(reservationID: String, sample: VoiceUsageSample) throws -> VoiceUsageLedger {
        try lock.withLock {
            let current = try currentUsageLedger()
            let settled = current.settling(reservationID: reservationID, sample: sample)
            try persistence.save(settled, updatedAt: now())
            return settled
        }
    }

    private func currentUsageLedger() throws -> VoiceUsageLedger {
        let currentPolicy = try policy()
        let timeZone = TimeZone(identifier: currentPolicy.schedule.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = now()
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let stored = try persistence.latestUsageLedger() ?? VoiceUsageLedger(periodStart: monthStart)
        return stored.recording(
            VoiceUsageSample(inputAudioSeconds: 0, outputAudioSeconds: 0),
            at: date,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}

public enum VoiceBudgetError: LocalizedError {
    case capReached

    public var errorDescription: String? {
        "The $20 monthly Gemini Live cap has been reached."
    }
}
