import Foundation
import ZoidCoachCore

public struct MissedPlanningInvitationRecoveryRequest: Equatable, Sendable {
    public let previousHeartbeat: Date
    public let startupAt: Date
    public let timeZoneIdentifier: String
    public let planningTime: LocalTime
    public let lastRecoveredLocalDay: String?
    public let lastRecoveredTimeZoneIdentifier: String?

    public init(
        previousHeartbeat: Date,
        startupAt: Date,
        timeZoneIdentifier: String,
        planningTime: LocalTime,
        lastRecoveredLocalDay: String?,
        lastRecoveredTimeZoneIdentifier: String?
    ) {
        self.previousHeartbeat = previousHeartbeat
        self.startupAt = startupAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.planningTime = planningTime
        self.lastRecoveredLocalDay = lastRecoveredLocalDay
        self.lastRecoveredTimeZoneIdentifier = lastRecoveredTimeZoneIdentifier
    }
}

public enum MissedPlanningPlanDisposition: Equatable, Sendable {
    case drafted
    case retainedExisting
}

public enum MissedPlanningPlanPreparation: Equatable, Sendable {
    case drafted(itemCount: Int)
    case retainedExisting(itemCount: Int)
    case sourceUnavailable
}

public struct RecoveredPlanningInvitation: Equatable, Sendable {
    public let targetLocalDay: String
    public let targetDay: Date
    public let planDisposition: MissedPlanningPlanDisposition
    public let itemCount: Int
    public let notificationEpisode: PromptEpisode
}

public enum MissedPlanningInvitationRecoveryResult: Equatable, Sendable {
    case notRequired
    case alreadyRecovered(targetLocalDay: String)
    case sourceUnavailable(targetLocalDay: String)
    case recovered(RecoveredPlanningInvitation)
}

public struct MissedPlanningInvitationRecoveryService: Sendable {
    public init() {}

    public func recover(
        request: MissedPlanningInvitationRecoveryRequest,
        preparePlan: @Sendable (Date) async throws -> MissedPlanningPlanPreparation,
        enqueueInvitation: @Sendable (Date, Int, String) throws -> PromptEpisode,
        persistCheckpoint: @Sendable (String, Date, Date, String) throws -> Void
    ) async throws -> MissedPlanningInvitationRecoveryResult {
        guard let recovery = MissedNightlyRunCalculator().recoveryRun(
            sleepStartedAt: request.previousHeartbeat,
            wokeAt: request.startupAt,
            policy: NightlyReplayPolicy(
                timeZoneIdentifier: request.timeZoneIdentifier,
                planningTime: request.planningTime
            )
        ) else { return .notRequired }
        if request.lastRecoveredLocalDay == recovery.targetLocalDay,
           request.lastRecoveredTimeZoneIdentifier == request.timeZoneIdentifier {
            return .alreadyRecovered(targetLocalDay: recovery.targetLocalDay)
        }
        guard let targetDay = Self.date(
            localDay: recovery.targetLocalDay,
            timeZoneIdentifier: request.timeZoneIdentifier
        ) else { return .notRequired }

        let preparation = try await preparePlan(targetDay)
        let disposition: MissedPlanningPlanDisposition
        let itemCount: Int
        switch preparation {
        case let .drafted(count):
            disposition = .drafted
            itemCount = count
        case let .retainedExisting(count):
            disposition = .retainedExisting
            itemCount = count
        case .sourceUnavailable:
            return .sourceUnavailable(targetLocalDay: recovery.targetLocalDay)
        }
        let episode = try enqueueInvitation(
            targetDay,
            itemCount,
            request.timeZoneIdentifier
        )
        try persistCheckpoint(
            recovery.targetLocalDay,
            request.startupAt,
            request.previousHeartbeat,
            request.timeZoneIdentifier
        )
        return .recovered(RecoveredPlanningInvitation(
            targetLocalDay: recovery.targetLocalDay,
            targetDay: targetDay,
            planDisposition: disposition,
            itemCount: itemCount,
            notificationEpisode: episode
        ))
    }

    private static func date(localDay: String, timeZoneIdentifier: String) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = localDay.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: values[0],
            month: values[1],
            day: values[2]
        ))
    }
}
