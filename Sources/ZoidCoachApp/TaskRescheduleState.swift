import Foundation

struct TaskRescheduleState: Equatable, Sendable {
    let selectedDate: Date
    let earliestDate: Date

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: referenceDate)
        earliestDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        selectedDate = earliestDate
    }

    func validated(_ date: Date, calendar: Calendar = .current) -> Result<Date, ValidationError> {
        let normalized = calendar.startOfDay(for: date)
        guard normalized >= calendar.startOfDay(for: earliestDate) else { return .failure(.mustBeFuture) }
        return .success(normalized)
    }

    enum ValidationError: Error, Equatable {
        case mustBeFuture
        var message: String { "Choose tomorrow or a later date." }
    }
}
