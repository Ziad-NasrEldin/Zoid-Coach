import EventKit
import Foundation

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
