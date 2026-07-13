import CryptoKit
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class ActiveOfflineWorkEntryController: ObservableObject {
    typealias SaveAction = (_ id: String, _ sourceDay: String, _ taskID: String, _ startedAt: Date, _ durationMinutes: Int, _ note: String?) throws -> Void

    static let minimumMinutes = 5
    static let maximumMinutes = 240

    let taskID: String
    let taskTitle: String

    @Published var startedAt: Date
    @Published var durationMinutes = 15
    @Published var note = ""
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private let calendar: Calendar
    private let now: () -> Date
    private let saveAction: SaveAction

    init(
        taskID: String,
        taskTitle: String,
        startedAt: Date? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        saveAction: @escaping SaveAction
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.calendar = calendar
        self.now = now
        self.saveAction = saveAction
        self.startedAt = startedAt ?? now().addingTimeInterval(-15 * 60)
    }

    convenience init(
        taskID: String,
        taskTitle: String,
        runtimeEnvironment: RuntimeEnvironment = .current()
    ) {
        do {
            let policy = try PolicyStore(databaseURL: runtimeEnvironment.databaseURL).current()?.policy
                ?? UserPolicy.defaults()
            let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let store = try DailyReviewStore(databaseURL: runtimeEnvironment.databaseURL, timeZone: timeZone)
            self.init(taskID: taskID, taskTitle: taskTitle, calendar: calendar) {
                id, sourceDay, taskID, startedAt, durationMinutes, note in
                _ = try store.saveOfflineWork(
                    id: id,
                    sourceDay: sourceDay,
                    taskID: taskID,
                    startedAt: startedAt,
                    durationMinutes: durationMinutes,
                    note: note
                )
            }
        } catch {
            let setupError = error
            self.init(taskID: taskID, taskTitle: taskTitle) { _, _, _, _, _, _ in
                throw setupError
            }
        }
    }

    var canSave: Bool {
        !isSaving
            && successMessage == nil
            && (Self.minimumMinutes ... Self.maximumMinutes).contains(durationMinutes)
            && startedAt <= now()
            && recordedEnd <= now()
    }

    @discardableResult
    func save() -> Bool {
        guard !isSaving, successMessage == nil else { return false }
        guard (Self.minimumMinutes ... Self.maximumMinutes).contains(durationMinutes) else {
            errorMessage = "Choose between 5 minutes and 4 hours. Split longer work into separate entries."
            return false
        }
        guard startedAt <= now() else {
            errorMessage = "Start time cannot be in the future."
            return false
        }
        guard recordedEnd <= now() else {
            errorMessage = "The duration extends into the future. Choose an earlier start time or a shorter duration."
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try saveAction(
                entryID,
                sourceDay(for: startedAt),
                taskID,
                startedAt,
                durationMinutes,
                normalizedNote
            )
            errorMessage = nil
            successMessage = "Recorded \(durationMinutes) minutes away from the Mac for \(taskTitle). It will count as actual task time and remain separate from Screenwatch evidence."
            return true
        } catch {
            errorMessage = "Away-from-Mac work was not saved. \(error.localizedDescription)"
            return false
        }
    }

    private var normalizedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var recordedEnd: Date {
        startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var entryID: String {
        let startedAtMilliseconds = Int64((startedAt.timeIntervalSince1970 * 1_000).rounded())
        let input = Data("\(taskID)\u{1F}\(startedAtMilliseconds)\u{1F}\(durationMinutes)".utf8)
        let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return "active-offline-\(digest)"
    }

    private func sourceDay(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
