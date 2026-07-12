import EventKit
import Foundation
import ZoidCoachCore

struct CalendarCommitment: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isZoidOwned: Bool
}

struct ZoidCalendarBlock: Equatable, Sendable, Identifiable {
    let id: String
    let planItemID: String
    let start: Date
    let end: Date
}

struct CalendarChoice: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let isWritable: Bool

    var displayName: String {
        sourceTitle.isEmpty ? title : "\(title) (\(sourceTitle))"
    }
}

enum CalendarSelectionAvailability: Equatable, Sendable {
    case available
    case needsPermission
    case unavailable
}

@MainActor
protocol CalendarServicing: AnyObject {
    var isProductionAdapter: Bool { get }
    var selectionAvailability: CalendarSelectionAvailability { get }
    func availableCalendars() throws -> [CalendarChoice]
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
}

@MainActor
final class CalendarService: CalendarServicing {
    let isProductionAdapter = true
    private let store: EKEventStore
    private let zoidCalendarTitle = "Zoid Coach"
    private let ownershipPrefix = "zoid-coach:block:"

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var selectionAvailability: CalendarSelectionAvailability {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            .available
        case .notDetermined:
            .needsPermission
        case .denied, .restricted, .writeOnly:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func availableCalendars() throws -> [CalendarChoice] {
        guard hasFullAccess else { throw CalendarServiceError.accessUnavailable }
        return store.calendars(for: .event)
            .map {
                CalendarChoice(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title,
                    isWritable: $0.allowsContentModifications
                )
            }
            .sorted {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    func inspect() async -> SourceHealth {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return await authorizedHealth()
        case .notDetermined:
            return SourceHealth(
                id: .calendar,
                title: "Apple Calendar",
                eyebrow: "Capacity",
                state: .notConnected,
                detail: "Permission is ready to be requested",
                evidence: "Full access is required to schedule Zoid-owned work blocks",
                actionTitle: "Connect"
            )
        case .denied, .restricted, .writeOnly:
            return SourceHealth(
                id: .calendar,
                title: "Apple Calendar",
                eyebrow: "Capacity",
                state: .attention,
                detail: "Calendar access is unavailable",
                evidence: "Enable full access in System Settings before automatic scheduling",
                actionTitle: "Retry"
            )
        @unknown default:
            return SourceHealth(
                id: .calendar,
                title: "Apple Calendar",
                eyebrow: "Capacity",
                state: .attention,
                detail: "Calendar authorization state is not recognized",
                evidence: "No Calendar data was read or modified",
                actionTitle: "Inspect"
            )
        }
    }

    func requestAccessAndInspect() async -> SourceHealth {
        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { return await inspect() }
            _ = try ensureZoidCalendar()
            return await authorizedHealth()
        } catch {
            return SourceHealth(
                id: .calendar,
                title: "Apple Calendar",
                eyebrow: "Capacity",
                state: .attention,
                detail: "Calendar permission request or setup failed",
                evidence: "No Zoid work block was created",
                actionTitle: "Retry"
            )
        }
    }

    func commitments(from start: Date, through end: Date) throws -> [CalendarCommitment] {
        guard hasFullAccess else { throw CalendarServiceError.accessUnavailable }
        let zoidCalendarID = try ensureZoidCalendar().calendarIdentifier
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map {
                CalendarCommitment(
                    id: $0.calendarItemIdentifier,
                    title: $0.title,
                    start: $0.startDate,
                    end: $0.endDate,
                    isZoidOwned: $0.calendar.calendarIdentifier == zoidCalendarID && ($0.notes ?? "").contains(ownershipPrefix)
                )
            }
            .sorted { $0.start < $1.start }
    }

    func freeIntervals(in workWindow: CalendarInterval, commitments: [CalendarCommitment]) -> [CalendarInterval] {
        var cursor = workWindow.start
        var result: [CalendarInterval] = []
        for commitment in commitments.sorted(by: { $0.start < $1.start }) {
            guard commitment.end > workWindow.start, commitment.start < workWindow.end else { continue }
            let occupiedStart = max(commitment.start, workWindow.start)
            let occupiedEnd = min(commitment.end, workWindow.end)
            if cursor < occupiedStart {
                result.append(CalendarInterval(start: cursor, end: occupiedStart))
            }
            cursor = max(cursor, occupiedEnd)
        }
        if cursor < workWindow.end {
            result.append(CalendarInterval(start: cursor, end: workWindow.end))
        }
        return result
    }

    func createBlock(title: String, start: Date, end: Date, planItemID: String) throws -> ZoidCalendarBlock {
        guard hasFullAccess else { throw CalendarServiceError.accessUnavailable }
        let calendar = try ensureZoidCalendar()
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = ownershipPrefix + planItemID
        try store.save(event, span: .thisEvent, commit: true)
        return ZoidCalendarBlock(id: event.calendarItemIdentifier, planItemID: planItemID, start: start, end: end)
    }

    func existingBlock(for planItemID: String, from start: Date, through end: Date) throws -> ZoidCalendarBlock? {
        guard hasFullAccess else { throw CalendarServiceError.accessUnavailable }
        let calendar = try ensureZoidCalendar()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        guard let event = store.events(matching: predicate).first(where: { ($0.notes ?? "").contains(ownershipPrefix + planItemID) }) else {
            return nil
        }
        return ZoidCalendarBlock(
            id: event.calendarItemIdentifier,
            planItemID: planItemID,
            start: event.startDate,
            end: event.endDate
        )
    }

    func createConfirmedMeeting(title: String, start: Date, durationMinutes: Int) throws -> String {
        guard hasFullAccess,
              let calendar = store.defaultCalendarForNewEvents
        else { throw CalendarServiceError.accessUnavailable }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(max(1, durationMinutes) * 60))
        event.notes = "Created by Zoid Coach after a confirmed local meeting detection."
        try store.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
    }

    private func ensureZoidCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == zoidCalendarTitle }) {
            return existing
        }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first else {
            throw CalendarServiceError.calendarUnavailable
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = zoidCalendarTitle
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func authorizedHealth() async -> SourceHealth {
        let calendarCount = store.calendars(for: .event).count
        let zoidCalendarExists = store.calendars(for: .event).contains { $0.title == zoidCalendarTitle }
        return SourceHealth(
            id: .calendar,
            title: "Apple Calendar",
            eyebrow: "Capacity",
            state: .healthy,
            detail: zoidCalendarExists ? "Zoid Coach work calendar is ready" : "Calendar access is ready",
            evidence: "EventKit full access · \(calendarCount.formatted()) calendars discovered",
            actionTitle: "Refresh"
        )
    }

    private var hasFullAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: true
        default: false
        }
    }
}

@MainActor
final class DisabledQACalendarService: CalendarServicing {
    let isProductionAdapter = false
    var selectionAvailability: CalendarSelectionAvailability { .unavailable }
    func availableCalendars() throws -> [CalendarChoice] { [] }
    func inspect() async -> SourceHealth { health }
    func requestAccessAndInspect() async -> SourceHealth { health }

    private var health: SourceHealth {
        SourceHealth(
            id: .calendar,
            title: "Apple Calendar",
            eyebrow: "Capacity",
            state: .unavailable,
            detail: "QA Calendar integration is disabled",
            evidence: "A deterministic QA Calendar adapter is required before EventKit access is enabled",
            actionTitle: "Unavailable"
        )
    }
}

enum CalendarServiceError: LocalizedError {
    case accessUnavailable
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessUnavailable: "Apple Calendar full access is unavailable"
        case .calendarUnavailable: "A Calendar source is unavailable for Zoid Coach"
        }
    }
}
