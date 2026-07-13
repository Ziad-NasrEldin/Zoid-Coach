import Foundation

struct RemindersContinuityState: Equatable, Sendable {
    let isOutage: Bool
    let plannedTaskCount: Int
    let plannedEstimateMinutes: Int
    let hasActiveSession: Bool

    var title: String {
        isOutage ? "REMINDERS UNAVAILABLE / LOCAL WORK CONTINUES" : "REMINDERS CONNECTED"
    }

    var detail: String {
        guard isOutage else {
            return "Apple Reminders is connected. Local plan and timing data remain stored separately."
        }
        let plan = plannedTaskCount == 1 ? "1 planned task" : "\(plannedTaskCount) planned tasks"
        let session = hasActiveSession ? " Your active session keeps tracking locally." : ""
        return "Your \(plan), \(plannedEstimateMinutes) estimated minutes, and local history remain on this Mac.\(session) Create or continue local work now, then repair sync when convenient."
    }
}
