import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class QAFixtureRemindersService: RemindersServicing {
    let isProductionAdapter = false
    private let adapter: DeterministicOSFixtureAdapters

    init(adapter: DeterministicOSFixtureAdapters) { self.adapter = adapter }

    func inspect() async -> SourceHealth {
        do {
            let permission = try adapter.permission(.reminders)
            let count = try permission == .granted
                ? adapter.allReminders(includeCompleted: false).count
                : 0
            return Self.health(permission: permission, count: count)
        } catch {
            return Self.unavailable(error.localizedDescription)
        }
    }

    func requestAccessAndInspect() async -> SourceHealth { await inspect() }

    func discoverLists() async -> ReminderListLoad {
        do {
            guard try adapter.permission(.reminders) == .granted else {
                return .unavailable("QA Reminders permission is not granted.")
            }
            return .available(try adapter.snapshot().reminderLists.map {
                ReminderListChoice(id: $0.id, name: $0.name)
            })
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func fetchIncompleteTasks() async -> ReminderTaskLoad {
        do {
            return .available(try adapter.allReminders(includeCompleted: false).map {
                ReminderTask(
                    id: $0.id,
                    title: $0.title,
                    listID: $0.listIdentifier,
                    listName: $0.listIdentifier,
                    dueDate: $0.dueDate,
                    priority: $0.priority,
                    notes: $0.notes,
                    modificationDate: nil
                )
            })
        } catch {
            return .unavailable
        }
    }

    private static func health(permission: QAFixturePermissionState, count: Int) -> SourceHealth {
        return switch permission {
        case .granted:
            SourceHealth(
                id: .reminders, title: "QA Reminders", eyebrow: "Intent",
                state: .healthy, detail: "\(count) fixture reminders available",
                evidence: "Deterministic QA fixture state", actionTitle: "Refresh"
            )
        case .notDetermined:
            SourceHealth(
                id: .reminders, title: "QA Reminders", eyebrow: "Intent",
                state: .notConnected, detail: "Fixture permission is not determined",
                evidence: "Set permission through the QA control file", actionTitle: "Deferred"
            )
        case .denied, .restricted:
            SourceHealth(
                id: .reminders, title: "QA Reminders", eyebrow: "Intent",
                state: .attention, detail: "Fixture permission is \(permission.rawValue)",
                evidence: "No production Reminders access was attempted", actionTitle: "Inspect"
            )
        }
    }

    private static func unavailable(_ detail: String) -> SourceHealth {
        SourceHealth(
            id: .reminders, title: "QA Reminders", eyebrow: "Intent",
            state: .unavailable, detail: detail,
            evidence: "Fixture state could not be read", actionTitle: "Inspect"
        )
    }
}

@MainActor
final class QAFixtureCalendarService: CalendarServicing {
    let isProductionAdapter = false
    private let adapter: DeterministicOSFixtureAdapters

    init(adapter: DeterministicOSFixtureAdapters) { self.adapter = adapter }

    var selectionAvailability: CalendarSelectionAvailability {
        guard let permission = try? adapter.permission(.calendar) else { return .unavailable }
        return switch permission {
        case .granted: .available
        case .notDetermined: .needsPermission
        case .denied, .restricted: .unavailable
        }
    }

    func availableCalendars() throws -> [CalendarChoice] {
        guard try adapter.permission(.calendar) == .granted else {
            throw CalendarServiceError.accessUnavailable
        }
        let identifiers = Set(try adapter.snapshot().calendarCommitments.map(\.calendarIdentifier))
        return identifiers.sorted().map {
            CalendarChoice(id: $0, title: $0, sourceTitle: "QA Fixture", isWritable: true)
        }
    }

    func inspect() async -> SourceHealth {
        do {
            switch try adapter.permission(.calendar) {
            case .granted:
                return SourceHealth(
                    id: .calendar, title: "QA Calendar", eyebrow: "Capacity",
                    state: .healthy, detail: "Fixture Calendar is available",
                    evidence: "Owned mutations are enforced by fixture tokens", actionTitle: "Refresh"
                )
            case .notDetermined:
                return SourceHealth(
                    id: .calendar, title: "QA Calendar", eyebrow: "Capacity",
                    state: .notConnected, detail: "Fixture permission is not determined",
                    evidence: "Set permission through the QA control file", actionTitle: "Deferred"
                )
            case .denied, .restricted:
                return SourceHealth(
                    id: .calendar, title: "QA Calendar", eyebrow: "Capacity",
                    state: .attention, detail: "Fixture Calendar permission is unavailable",
                    evidence: "No production Calendar access was attempted", actionTitle: "Inspect"
                )
            }
        } catch {
            return SourceHealth(
                id: .calendar, title: "QA Calendar", eyebrow: "Capacity",
                state: .unavailable, detail: error.localizedDescription,
                evidence: "Fixture state could not be read", actionTitle: "Inspect"
            )
        }
    }

    func requestAccessAndInspect() async -> SourceHealth { await inspect() }
}

@MainActor
final class QAFixtureNotificationService: NotificationServicing {
    let isProductionAdapter = false
    private let adapter: DeterministicOSFixtureAdapters

    init(adapter: DeterministicOSFixtureAdapters) { self.adapter = adapter }

    func inspect() async -> SourceHealth {
        do {
            switch try adapter.permission(.notifications) {
            case .granted:
                return SourceHealth(
                    id: .notifications, title: "QA Notifications", eyebrow: "Escalation",
                    state: .healthy, detail: "Fixture notifications are available",
                    evidence: "Delivery and actions persist below the QA root", actionTitle: "Inspect"
                )
            case .notDetermined:
                return SourceHealth(
                    id: .notifications, title: "QA Notifications", eyebrow: "Escalation",
                    state: .notConnected, detail: "Fixture permission is not determined",
                    evidence: "Set permission through the QA control file", actionTitle: "Deferred"
                )
            case .denied, .restricted:
                return SourceHealth(
                    id: .notifications, title: "QA Notifications", eyebrow: "Escalation",
                    state: .attention, detail: "Fixture notification permission is unavailable",
                    evidence: "No production notification center was touched", actionTitle: "Inspect"
                )
            }
        } catch {
            return SourceHealth(
                id: .notifications, title: "QA Notifications", eyebrow: "Escalation",
                state: .unavailable, detail: error.localizedDescription,
                evidence: "Fixture state could not be read", actionTitle: "Inspect"
            )
        }
    }

    func requestAccessAndInspect() async -> SourceHealth { await inspect() }
}
