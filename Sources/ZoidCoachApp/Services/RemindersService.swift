import EventKit
import Foundation

struct ReminderTask: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let listID: String
    let listName: String
    let dueDate: Date?
    let priority: Int
    let notes: String?
    let modificationDate: Date?

    var dueLabel: String? {
        guard let dueDate else { return nil }
        return dueDate.formatted(.dateTime.month(.abbreviated).day())
    }
}

enum ReminderTaskLoad: Sendable {
    case available([ReminderTask])
    case unavailable
}

@MainActor
protocol RemindersServicing: AnyObject {
    var isProductionAdapter: Bool { get }
    func inspect() async -> SourceHealth
    func requestAccessAndInspect() async -> SourceHealth
    func fetchIncompleteTasks() async -> ReminderTaskLoad
}

@MainActor
final class RemindersService: RemindersServicing {
    let isProductionAdapter = true
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func inspect() async -> SourceHealth {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess, .authorized:
            return await authorizedHealth()
        case .notDetermined:
            return SourceHealth(
                id: .reminders,
                title: "Apple Reminders",
                eyebrow: "Intent",
                state: .notConnected,
                detail: "Permission is ready to be requested",
                evidence: "EventKit full access is required for task sync",
                actionTitle: "Connect"
            )
        case .denied, .restricted, .writeOnly:
            return SourceHealth(
                id: .reminders,
                title: "Apple Reminders",
                eyebrow: "Intent",
                state: .attention,
                detail: "Reminders access is unavailable",
                evidence: "Enable full access in System Settings",
                actionTitle: "Retry"
            )
        @unknown default:
            return SourceHealth(
                id: .reminders,
                title: "Apple Reminders",
                eyebrow: "Intent",
                state: .attention,
                detail: "Authorization state is not recognized",
                evidence: "No task data was read",
                actionTitle: "Inspect"
            )
        }
    }

    func requestAccessAndInspect() async -> SourceHealth {
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { return await inspect() }
            return await authorizedHealth()
        } catch {
            return SourceHealth(
                id: .reminders,
                title: "Apple Reminders",
                eyebrow: "Intent",
                state: .attention,
                detail: "Reminders permission request failed",
                evidence: "No task data was read or modified",
                actionTitle: "Retry"
            )
        }
    }

    func fetchIncompleteTasks() async -> ReminderTaskLoad {
        guard hasFullAccess else { return .unavailable }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let tasks: [ReminderTask] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                DispatchQueue.main.async {
                    continuation.resume(returning: (reminders ?? []).map {
                        ReminderTask(
                        id: $0.calendarItemIdentifier,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : $0.title,
                            listID: $0.calendar.calendarIdentifier,
                            listName: $0.calendar.title,
                            dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:)),
                            priority: $0.priority,
                            notes: $0.notes,
                            modificationDate: $0.lastModifiedDate
                        )
                    })
                }
            }
        }

        return .available(tasks
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            })
    }

    func completeTask(id: String) async -> Bool {
        guard hasFullAccess,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return false }

        do {
            reminder.isCompleted = true
            reminder.completionDate = Date()
            try store.save(reminder, commit: true)
            return (store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted == true
        } catch {
            return false
        }
    }

    func createTask(title: String, dueDate: Date) async -> Bool {
        guard hasFullAccess,
              let calendar = store.defaultCalendarForNewReminders()
        else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: dueDate
        )
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func authorizedHealth() async -> SourceHealth {
        let reminderCount = await fetchIncompleteReminderCount()
        let listCount = store.calendars(for: .reminder).count

        return SourceHealth(
            id: .reminders,
            title: "Apple Reminders",
            eyebrow: "Intent",
            state: .healthy,
            detail: "\(reminderCount.formatted()) incomplete reminders available",
            evidence: "EventKit full access · \(listCount.formatted()) lists discovered",
            actionTitle: "Refresh"
        )
    }

    private var hasFullAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: true
        default: false
        }
    }

    private func fetchIncompleteReminderCount() async -> Int {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.count ?? 0)
            }
        }
    }
}

@MainActor
final class DisabledQARemindersService: RemindersServicing {
    let isProductionAdapter = false
    private let detail: String

    init(detail: String = "QA Reminders integration is disabled") {
        self.detail = detail
    }
    func inspect() async -> SourceHealth { health }
    func requestAccessAndInspect() async -> SourceHealth { health }
    func fetchIncompleteTasks() async -> ReminderTaskLoad { .unavailable }

    private var health: SourceHealth {
        SourceHealth(
            id: .reminders,
            title: "Apple Reminders",
            eyebrow: "Intent",
            state: .unavailable,
            detail: detail,
            evidence: "A deterministic QA Reminders adapter is required before EventKit access is enabled",
            actionTitle: "Unavailable"
        )
    }
}
