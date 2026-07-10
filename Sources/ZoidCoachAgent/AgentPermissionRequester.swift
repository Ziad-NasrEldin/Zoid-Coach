import AppKit
import EventKit
import Foundation

@MainActor
enum AgentPermissionRequester {
    static func remindersStatus() -> String {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: "full_access"
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .writeOnly: "write_only"
        @unknown default: "unknown"
        }
    }

    static func requestRemindersAccess() async throws -> Bool {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let store = EKEventStore()
        return try await store.requestFullAccessToReminders()
    }
}
