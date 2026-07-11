import Foundation

public protocol ReplayClock: Sendable {
    var now: Date { get }
}

public struct FixedReplayClock: ReplayClock, Equatable, Sendable {
    public let now: Date

    public init(now: Date) {
        self.now = now
    }
}

public protocol IdentifierGenerator: Sendable {
    func nextIdentifier() -> String
}

public final class SequenceIdentifierGenerator: IdentifierGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var nextValue: Int

    public init(prefix: String = "event", startingAt: Int = 1) {
        self.prefix = prefix
        nextValue = startingAt
    }

    public func nextIdentifier() -> String {
        lock.lock()
        defer { lock.unlock() }
        let identifier = "\(prefix)-\(String(format: "%06d", nextValue))"
        nextValue += 1
        return identifier
    }
}

public enum SimulatedReminderEvent: Equatable, Codable, Sendable {
    case upserted(id: String, title: String, estimateMinutes: Int?)
    case removed(id: String)
}

public enum SimulatedCalendarEvent: Equatable, Codable, Sendable {
    case reserved(id: String, start: Date, end: Date)
    case removed(id: String)
}

public enum SimulatedBehaviorEvent: Equatable, Codable, Sendable {
    case observed(application: String?, classification: BehaviorClassification)
}

public enum SimulatedPromptEvent: Equatable, Codable, Sendable {
    case presented(id: String, topic: String)
    case responded(id: String, response: String)
    case dismissed(id: String)
}

public enum SimulatedActionEvent: Equatable, Codable, Sendable {
    case recorded(id: String, name: String, succeeded: Bool)
    case nightlyPlanExecuted(targetLocalDay: String, delayedAfterWake: Bool)
}

public enum SimulatedDayEventKind: Equatable, Codable, Sendable {
    case reminder(SimulatedReminderEvent)
    case calendar(SimulatedCalendarEvent)
    case behavior(SimulatedBehaviorEvent)
    case sleep
    case wake
    case prompt(SimulatedPromptEvent)
    case action(SimulatedActionEvent)
}

public struct SimulatedDayEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let occurredAt: Date
    public let timeZoneIdentifier: String
    public let localDay: String
    public let kind: SimulatedDayEventKind

    public init(id: String, occurredAt: Date, timeZoneIdentifier: String, localDay: String, kind: SimulatedDayEventKind) {
        self.id = id
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDay = localDay
        self.kind = kind
    }
}

public struct SimulatedReminderSnapshot: Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let estimateMinutes: Int?
}

public struct SimulatedCalendarReservation: Equatable, Codable, Sendable {
    public let id: String
    public let start: Date
    public let end: Date
}

public struct SimulatedPromptSnapshot: Equatable, Codable, Sendable {
    public let id: String
    public let topic: String
    public let response: String?
    public let isDismissed: Bool
}

public struct SimulatedActionSnapshot: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let succeeded: Bool
}

public struct NightlyPlanningRun: Equatable, Codable, Sendable {
    public let targetLocalDay: String
    public let executedAt: Date
    public let delayedAfterWake: Bool
    public let policyVersion: Int
}

public struct DeterministicReplayState: Equatable, Codable, Sendable {
    public internal(set) var reminders: [String: SimulatedReminderSnapshot] = [:]
    public internal(set) var calendarReservations: [String: SimulatedCalendarReservation] = [:]
    public internal(set) var behaviorObservations: [BehaviorObservation] = []
    public internal(set) var isSleeping = false
    public internal(set) var sleepStartedAt: Date?
    public internal(set) var prompts: [String: SimulatedPromptSnapshot] = [:]
    public internal(set) var actions: [String: SimulatedActionSnapshot] = [:]
    public internal(set) var nightlyPlanningRuns: [NightlyPlanningRun] = []
    public internal(set) var processedEventIDs: Set<String> = []

    public init() {}
}

public struct SimulatedDayFixture: Sendable {
    private let clock: any ReplayClock
    private let identifiers: any IdentifierGenerator
    private let timeZone: TimeZone

    public init(clock: any ReplayClock, identifiers: any IdentifierGenerator, timeZone: TimeZone) {
        self.clock = clock
        self.identifiers = identifiers
        self.timeZone = timeZone
    }

    public func event(at date: Date? = nil, kind: SimulatedDayEventKind) -> SimulatedDayEvent {
        let occurredAt = date ?? clock.now
        return SimulatedDayEvent(
            id: identifiers.nextIdentifier(),
            occurredAt: occurredAt,
            timeZoneIdentifier: timeZone.identifier,
            localDay: Self.localDay(for: occurredAt, timeZone: timeZone),
            kind: kind
        )
    }

    private static func localDay(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public struct DeterministicDayReplay: Sendable {
    public static func replay<S: Sequence>(
        _ events: S,
        initialState: DeterministicReplayState = DeterministicReplayState(),
        nightlyPolicy: NightlyReplayPolicy? = nil
    ) -> DeterministicReplayState where S.Element == SimulatedDayEvent {
        events.sorted(by: eventOrder).reduce(into: initialState) { state, event in
            reduce(event, into: &state, nightlyPolicy: nightlyPolicy)
        }
    }

    public static func reduce(
        _ event: SimulatedDayEvent,
        into state: inout DeterministicReplayState,
        nightlyPolicy: NightlyReplayPolicy? = nil
    ) {
        guard state.processedEventIDs.insert(event.id).inserted else { return }
        switch event.kind {
        case let .reminder(reminder):
            switch reminder {
            case let .upserted(id, title, estimateMinutes):
                state.reminders[id] = SimulatedReminderSnapshot(id: id, title: title, estimateMinutes: estimateMinutes)
            case let .removed(id):
                state.reminders[id] = nil
            }
        case let .calendar(calendar):
            switch calendar {
            case let .reserved(id, start, end):
                state.calendarReservations[id] = SimulatedCalendarReservation(id: id, start: start, end: end)
            case let .removed(id):
                state.calendarReservations[id] = nil
            }
        case let .behavior(behavior):
            switch behavior {
            case let .observed(application, classification):
                state.behaviorObservations.append(BehaviorObservation(observedAt: event.occurredAt, application: application, classification: classification))
            }
        case .sleep:
            state.isSleeping = true
            state.sleepStartedAt = event.occurredAt
        case .wake:
            let sleepStartedAt = state.sleepStartedAt
            state.isSleeping = false
            state.sleepStartedAt = nil
            if let nightlyPolicy,
               let sleepStartedAt,
               let run = MissedNightlyRunCalculator().recoveryRun(
                   sleepStartedAt: sleepStartedAt,
                   wokeAt: event.occurredAt,
                   policy: nightlyPolicy,
                   alreadyExecutedTargetDays: Set(state.nightlyPlanningRuns.map(\.targetLocalDay))
               ) {
                state.nightlyPlanningRuns.append(run)
            }
        case let .prompt(prompt):
            switch prompt {
            case let .presented(id, topic):
                state.prompts[id] = SimulatedPromptSnapshot(id: id, topic: topic, response: nil, isDismissed: false)
            case let .responded(id, response):
                guard let existing = state.prompts[id] else { break }
                state.prompts[id] = SimulatedPromptSnapshot(id: id, topic: existing.topic, response: response, isDismissed: false)
            case let .dismissed(id):
                guard let existing = state.prompts[id] else { break }
                state.prompts[id] = SimulatedPromptSnapshot(id: id, topic: existing.topic, response: existing.response, isDismissed: true)
            }
        case let .action(action):
            switch action {
            case let .recorded(id, name, succeeded):
                state.actions[id] = SimulatedActionSnapshot(id: id, name: name, succeeded: succeeded)
            case let .nightlyPlanExecuted(targetLocalDay, delayedAfterWake):
                guard state.nightlyPlanningRuns.contains(where: { $0.targetLocalDay == targetLocalDay }) == false else { break }
                state.nightlyPlanningRuns.append(NightlyPlanningRun(targetLocalDay: targetLocalDay, executedAt: event.occurredAt, delayedAfterWake: delayedAfterWake, policyVersion: nightlyPolicy?.version ?? 1))
            }
        }
    }

    private static func eventOrder(_ lhs: SimulatedDayEvent, _ rhs: SimulatedDayEvent) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        return lhs.id < rhs.id
    }
}

public struct NightlyReplayPolicy: Equatable, Codable, Sendable {
    public let version: Int
    public let timeZoneIdentifier: String
    public let planningTime: LocalTime

    public init(version: Int = 1, timeZoneIdentifier: String, planningTime: LocalTime) {
        self.version = version
        self.timeZoneIdentifier = timeZoneIdentifier
        self.planningTime = planningTime
    }
}

public struct MissedNightlyRunCalculator: Sendable {
    public init() {}

    public func recoveryRun(
        sleepStartedAt: Date,
        wokeAt: Date,
        policy: NightlyReplayPolicy,
        alreadyExecutedTargetDays: Set<String> = []
    ) -> NightlyPlanningRun? {
        guard sleepStartedAt < wokeAt,
              let timeZone = TimeZone(identifier: policy.timeZoneIdentifier)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let finalDay = calendar.startOfDay(for: wokeAt)
        var latestMissedTrigger: Date?
        let previousDay = calendar.date(byAdding: .day, value: -1, to: finalDay)
        for day in [finalDay, previousDay].compactMap({ $0 }) {
            if let trigger = scheduledTime(on: day, localTime: policy.planningTime, calendar: calendar),
               trigger > sleepStartedAt,
               trigger <= wokeAt {
                latestMissedTrigger = trigger
                break
            }
        }

        guard let trigger = latestMissedTrigger,
              let targetDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trigger))
        else { return nil }
        let targetDay = localDay(for: targetDate, calendar: calendar)
        guard alreadyExecutedTargetDays.contains(targetDay) == false else { return nil }
        return NightlyPlanningRun(targetLocalDay: targetDay, executedAt: wokeAt, delayedAfterWake: true, policyVersion: policy.version)
    }

    private func scheduledTime(on day: Date, localTime: LocalTime, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        return calendar.nextDate(
            after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: localTime.hour, minute: localTime.minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ).flatMap { calendar.isDate($0, inSameDayAs: start) ? $0 : nil }
    }

    private func localDay(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
