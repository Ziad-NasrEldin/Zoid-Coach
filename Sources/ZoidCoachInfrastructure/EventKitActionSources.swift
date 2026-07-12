import EventKit
import Foundation
import ZoidCoachCore

public final class EventKitTaskSource: TaskSource, @unchecked Sendable {
    private let store: EKEventStore
    private let calendar: Calendar
    private let lock = NSLock()
    private let metadataPrefix = "zoid-coach:marker:"

    public init(store: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func task(identifier: String) async throws -> SourceTask? {
        try lock.withLock {
            try requireReminderAccess()
            guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return nil }
            return normalized(reminder)
        }
    }

    public func task(metadataMarker: String) async throws -> SourceTask? {
        try requireReminderAccess()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self else {
                    continuation.resume(throwing: ActionSourceError.temporarilyUnavailable)
                    return
                }
                let match = reminders?.first { self.ownedMetadata(in: $0.notes) == metadataMarker }
                continuation.resume(returning: match.map(self.normalized))
            }
        }
    }

    public func create(title: String, dueDate: Date?, listIdentifier: String?, metadataMarker: String?) async throws -> SourceTask {
        try lock.withLock {
            try requireReminderAccess()
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, metadataMarker?.contains("\n") != true else {
                throw ActionSourceError.invalidDesiredState
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = trimmedTitle
            if let listIdentifier {
                guard let list = store.calendar(withIdentifier: listIdentifier), list.allowedEntityTypes.contains(.reminder) else {
                    throw ActionSourceError.missingEntity
                }
                reminder.calendar = list
            } else {
                guard let list = store.defaultCalendarForNewReminders() else {
                    throw ActionSourceError.temporarilyUnavailable
                }
                reminder.calendar = list
            }
            reminder.dueDateComponents = dueDate.map {
                calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: $0)
            }
            reminder.notes = replacingOwnedMetadata(in: nil, with: metadataMarker)
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw mapEventKitError(error)
            }
            return normalized(reminder)
        }
    }

    public func apply(_ mutation: TaskSourceMutation, to identifier: String) async throws -> SourceTask {
        try lock.withLock {
            try requireReminderAccess()
            guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                throw ActionSourceError.missingEntity
            }

            switch mutation {
            case let .setPriority(priority):
                guard [0, 1, 5, 9].contains(priority) else { throw ActionSourceError.invalidDesiredState }
                reminder.priority = priority
            case let .setDueDate(date):
                reminder.dueDateComponents = date.map {
                    calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: $0)
                }
            case let .setMetadataMarker(marker):
                guard marker?.contains("\n") != true else { throw ActionSourceError.invalidDesiredState }
                reminder.notes = replacingOwnedMetadata(in: reminder.notes, with: marker)
            case let .complete(date):
                reminder.isCompleted = true
                reminder.completionDate = date
            }

            do {
                try store.save(reminder, commit: true)
            } catch {
                throw mapEventKitError(error)
            }
            guard let saved = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                throw ActionSourceError.temporarilyUnavailable
            }
            return normalized(saved)
        }
    }

    private func normalized(_ reminder: EKReminder) -> SourceTask {
        SourceTask(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled reminder",
            listIdentifier: reminder.calendar.calendarIdentifier,
            priority: reminder.priority,
            dueDate: reminder.dueDateComponents.flatMap(calendar.date(from:)),
            notes: reminder.notes,
            metadataMarker: ownedMetadata(in: reminder.notes),
            isCompleted: reminder.isCompleted
        )
    }

    private func replacingOwnedMetadata(in notes: String?, with marker: String?) -> String? {
        var lines = (notes ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix(metadataPrefix) }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if let marker, !marker.isEmpty { lines.append(metadataPrefix + marker) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func ownedMetadata(in notes: String?) -> String? {
        notes?.split(separator: "\n").lazy
            .map(String.init)
            .first { $0.hasPrefix(metadataPrefix) }
            .map { String($0.dropFirst(metadataPrefix.count)) }
    }

    private func requireReminderAccess() throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return
        case .notDetermined, .denied, .restricted, .writeOnly:
            throw ActionSourceError.accessDenied
        @unknown default:
            throw ActionSourceError.accessDenied
        }
    }
}

public final class EventKitCalendarSource: CalendarSource, CalendarAvailabilitySource, @unchecked Sendable {
    private let store: EKEventStore
    private let now: @Sendable () -> Date
    private let calendarTitle: String
    private let legacyCalendarTitle = "Zoid Coach"
    private let lock = NSLock()
    private let ownershipPrefix = "zoid-coach:block:"
    private let planItemPrefix = "zoid-coach:plan-item:"
    private let meetingPrefix = "zoid-coach:meeting:"

    public init(
        store: EKEventStore = EKEventStore(),
        calendarTitle: String = "Zoid 666",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.calendarTitle = calendarTitle
        self.now = now
    }

    public func commitment(identifier: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requireCalendarAccess()
            guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent else { return nil }
            return normalized(event)
        }
    }

    public func ownedCommitment(ownershipToken expectedToken: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requireCalendarAccess()
            return ownedCommitmentLocked(ownershipToken: expectedToken)
        }
    }

    public func confirmedMeeting(fingerprint: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requireCalendarAccess()
            return confirmedMeetingLocked(fingerprint: fingerprint)
        }
    }

    public func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [CalendarCommitment] {
        try lock.withLock {
            try requireCalendarAccess()
            let calendars = calendarIdentifiers.isEmpty
                ? nil
                : calendarIdentifiers.compactMap { store.calendar(withIdentifier: $0) }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            return store.events(matching: predicate)
                .filter { !$0.isAllDay }
                .map(normalized)
                .sorted { lhs, rhs in lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start }
        }
    }

    public func apply(_ mutation: CalendarSourceMutation) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requireCalendarAccess()
            do {
                switch mutation {
                case let .createBlock(block):
                    if let existing = ownedCommitmentLocked(ownershipToken: block.ownershipToken) { return existing }
                let event = EKEvent(eventStore: store)
                event.calendar = try requiredZoidCalendar()
                apply(block, to: event)
                try store.save(event, span: .thisEvent, commit: true)
                return normalized(event)

                case let .updateOwnedBlock(identifier, block):
                guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent else {
                    throw ActionSourceError.missingEntity
                }
                let zoidCalendarIdentifier = try requiredZoidCalendar().calendarIdentifier
                guard event.calendar.calendarIdentifier == zoidCalendarIdentifier,
                      ownershipToken(in: event.notes) == block.ownershipToken
                else { throw ActionSourceError.ownershipViolation }
                apply(block, to: event)
                try store.save(event, span: .thisEvent, commit: true)
                return normalized(event)

                case let .deleteOwnedBlock(identifier, token):
                guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent else { return nil }
                let zoidCalendarIdentifier = try requiredZoidCalendar().calendarIdentifier
                guard event.calendar.calendarIdentifier == zoidCalendarIdentifier,
                      ownershipToken(in: event.notes) == token
                else { throw ActionSourceError.ownershipViolation }
                try store.remove(event, span: .thisEvent, commit: true)
                return nil

                case let .createConfirmedMeeting(meeting):
                    if let existing = confirmedMeetingLocked(fingerprint: meeting.fingerprint) { return existing }
                    if let existing = duplicateMeetingLocked(meeting) { return existing }
                let event = EKEvent(eventStore: store)
                if let identifier = meeting.calendarIdentifier {
                    guard let selected = store.calendar(withIdentifier: identifier), selected.allowsContentModifications else {
                        throw ActionSourceError.invalidDesiredState
                    }
                    event.calendar = selected
                } else {
                    guard let selected = store.defaultCalendarForNewEvents else {
                        throw ActionSourceError.temporarilyUnavailable
                    }
                    event.calendar = selected
                }
                event.title = meeting.title
                event.startDate = meeting.start
                event.endDate = meeting.end
                event.location = meeting.location
                if let callLink = meeting.callLink.flatMap(URL.init(string:)) { event.url = callLink }
                var notes = [meetingPrefix + meeting.fingerprint]
                if !meeting.participants.isEmpty {
                    notes.append("Participants: " + meeting.participants.joined(separator: ", "))
                }
                if let timezoneIdentifier = meeting.timezoneIdentifier {
                    notes.append("Source timezone: " + timezoneIdentifier)
                }
                event.notes = notes.joined(separator: "\n")
                try store.save(event, span: .thisEvent, commit: true)
                return normalized(event)
                }
            } catch let error as ActionSourceError {
                throw error
            } catch {
                throw mapEventKitError(error)
            }
        }
    }

    private func ownedCommitmentLocked(ownershipToken expectedToken: String) -> CalendarCommitment? {
        guard let calendar = existingZoidCalendar() else { return nil }
        return events(calendars: [calendar]).first { ownershipToken(in: $0.notes) == expectedToken }.map(normalized)
    }

    private func confirmedMeetingLocked(fingerprint: String) -> CalendarCommitment? {
        events(calendars: nil).first { meetingFingerprint(in: $0.notes) == fingerprint }.map(normalized)
    }

    private func duplicateMeetingLocked(_ meeting: ConfirmedMeetingMutation) -> CalendarCommitment? {
        let candidate = MeetingCandidate(
            title: meeting.title,
            start: meeting.start,
            durationMinutes: max(1, Int(meeting.end.timeIntervalSince(meeting.start) / 60)),
            confidence: .high,
            requiresClarification: false,
            sourceText: "",
            participants: meeting.participants
        )
        let nearbyEvents = events(calendars: nil).filter {
            abs($0.startDate.timeIntervalSince(meeting.start)) <= MeetingCandidatePolicy().duplicateTolerance
        }
        let candidates = nearbyEvents.map {
            ExistingMeetingEvent(
                id: $0.calendarItemIdentifier,
                title: $0.title ?? "Untitled event",
                start: $0.startDate,
                end: $0.endDate,
                participants: self.participantNames(in: $0)
            )
        }
        guard case let .duplicate(identifier) = MeetingCandidatePolicy().route(candidate, existingEvents: candidates),
              let event = nearbyEvents.first(where: { $0.calendarItemIdentifier == identifier })
        else { return nil }
        return normalized(event)
    }

    private func participantNames(in event: EKEvent) -> [String] {
        guard let attendees = event.attendees else { return [] }
        return attendees.map { attendee in
            if let name = attendee.name { return name }
            return attendee.url.absoluteString
        }
    }

    private func apply(_ block: CalendarBlockMutation, to event: EKEvent) {
        event.title = block.title
        event.startDate = block.start
        event.endDate = block.end
        event.notes = [ownershipPrefix + block.ownershipToken, planItemPrefix + block.planItemID].joined(separator: "\n")
    }

    private func normalized(_ event: EKEvent) -> CalendarCommitment {
        CalendarCommitment(
            id: event.calendarItemIdentifier,
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            calendarIdentifier: event.calendar.calendarIdentifier,
            ownershipToken: ownershipToken(in: event.notes),
            meetingFingerprint: meetingFingerprint(in: event.notes),
            participants: participantNames(in: event)
        )
    }

    private func ownershipToken(in notes: String?) -> String? {
        markerValue(prefix: ownershipPrefix, notes: notes)
    }

    private func meetingFingerprint(in notes: String?) -> String? {
        markerValue(prefix: meetingPrefix, notes: notes)
    }

    private func markerValue(prefix: String, notes: String?) -> String? {
        notes?.split(separator: "\n").lazy
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func events(calendars: [EKCalendar]?) -> [EKEvent] {
        let reference = now()
        let start = Calendar(identifier: .gregorian).date(byAdding: .year, value: -5, to: reference) ?? reference.addingTimeInterval(-157_788_000)
        let end = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: reference) ?? reference.addingTimeInterval(315_576_000)
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
    }

    private func existingZoidCalendar() -> EKCalendar? {
        store.calendars(for: .event).first(where: {
            $0.title == calendarTitle
                || (calendarTitle == "Zoid 666" && $0.title == legacyCalendarTitle)
        })
    }

    private func requiredZoidCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle }) { return existing }
        if calendarTitle == "Zoid 666",
           let legacy = store.calendars(for: .event).first(where: { $0.title == legacyCalendarTitle }) {
            legacy.title = calendarTitle
            do {
                try store.saveCalendar(legacy, commit: true)
                return legacy
            } catch {
                throw mapEventKitError(error)
            }
        }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first else {
            throw ActionSourceError.temporarilyUnavailable
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            throw mapEventKitError(error)
        }
    }

    private func requireCalendarAccess() throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return
        case .notDetermined, .denied, .restricted, .writeOnly:
            throw ActionSourceError.accessDenied
        @unknown default:
            throw ActionSourceError.accessDenied
        }
    }
}

private func mapEventKitError(_ error: Error) -> ActionSourceError {
    let nsError = error as NSError
    guard nsError.domain == EKErrorDomain,
          let code = EKError.Code(rawValue: nsError.code)
    else { return .temporarilyUnavailable }
    switch code {
    case .eventStoreNotAuthorized:
        return .accessDenied
    case .calendarReadOnly, .noCalendar, .datesInverted, .objectBelongsToDifferentStore:
        return .invalidDesiredState
    default:
        return .temporarilyUnavailable
    }
}
