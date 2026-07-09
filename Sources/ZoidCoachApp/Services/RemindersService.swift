import EventKit
import Foundation

struct ReminderTask: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let listName: String
    let dueDate: Date?

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
final class RemindersService {
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
                            listName: $0.calendar.title,
                            dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:))
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
