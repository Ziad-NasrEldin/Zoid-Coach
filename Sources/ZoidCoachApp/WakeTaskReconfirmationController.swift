import Foundation

struct WakeTaskReconfirmation: Identifiable, Equatable {
    let taskID: String
    let taskTitle: String
    let inactiveSince: Date
    let returnedAt: Date

    var id: String { taskID }

    var inactiveDuration: TimeInterval {
        max(0, returnedAt.timeIntervalSince(inactiveSince))
    }

    var durationLabel: String {
        let minutes = max(1, Int(inactiveDuration / 60))
        if minutes < 60 {
            return "about \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "about \(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "about \(hours)h \(remainder)m"
    }
}

struct WakeTaskReconciliationNotice: Equatable {
    let taskTitle: String
    let inactiveDuration: TimeInterval

    var message: String {
        let minutes = max(1, Int(inactiveDuration / 60))
        return "Back after about \(minutes) minute\(minutes == 1 ? "" : "s"). \(taskTitle) stayed active. Only observed activity counts as aligned work."
    }
}

@MainActor
final class WakeTaskReconfirmationController: ObservableObject {
    @Published private(set) var pendingConfirmation: WakeTaskReconfirmation?
    @Published private(set) var notice: WakeTaskReconciliationNotice?

    let longAbsenceThreshold: TimeInterval
    private var inactiveSince: Date?

    init(longAbsenceThreshold: TimeInterval = 5 * 60) {
        self.longAbsenceThreshold = max(60, longAbsenceThreshold)
    }

    func noteInactive(at date: Date = Date()) {
        if inactiveSince == nil {
            inactiveSince = date
        }
    }

    func reconcileActivation(
        activeTaskID: String?,
        taskTitle: String?,
        at returnedAt: Date = Date()
    ) {
        guard let inactiveSince else { return }
        self.inactiveSince = nil
        notice = nil

        guard let activeTaskID,
              let taskTitle,
              taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            pendingConfirmation = nil
            return
        }

        let absence = max(0, returnedAt.timeIntervalSince(inactiveSince))
        guard absence >= longAbsenceThreshold else {
            pendingConfirmation = nil
            notice = WakeTaskReconciliationNotice(
                taskTitle: taskTitle,
                inactiveDuration: absence
            )
            return
        }

        pendingConfirmation = WakeTaskReconfirmation(
            taskID: activeTaskID,
            taskTitle: taskTitle,
            inactiveSince: inactiveSince,
            returnedAt: returnedAt
        )
    }

    func confirmTaskIsStillActive() {
        guard let pendingConfirmation else { return }
        notice = WakeTaskReconciliationNotice(
            taskTitle: pendingConfirmation.taskTitle,
            inactiveDuration: pendingConfirmation.inactiveDuration
        )
        self.pendingConfirmation = nil
    }

    func confirmTaskWasInterrupted() {
        pendingConfirmation = nil
        notice = nil
    }

    func dismissNotice() {
        notice = nil
    }
}
