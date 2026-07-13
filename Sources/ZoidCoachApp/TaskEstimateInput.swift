import Foundation

enum TaskEstimateInput {
    static let maximumMinutes = 480

    static func parse(_ rawValue: String) -> Result<Int, ValidationError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let minutes = Int(trimmed) else { return .failure(.malformed) }
        guard minutes > 0 else { return .failure(.nonPositive) }
        guard minutes <= maximumMinutes else { return .failure(.tooLarge(maximum: maximumMinutes)) }
        return .success(minutes)
    }

    enum ValidationError: Error, Equatable {
        case empty
        case malformed
        case nonPositive
        case tooLarge(maximum: Int)

        var message: String {
            switch self {
            case .empty: "Enter an estimate in minutes."
            case .malformed: "Use a whole number of minutes, such as 25."
            case .nonPositive: "Estimate must be at least 1 minute."
            case let .tooLarge(maximum): "Estimate must be \(maximum) minutes or less. Split larger work into smaller tasks."
            }
        }
    }
}
