import Foundation

struct GamingManualAdjustmentPresentation: Identifiable, Equatable {
    let id: UUID
    let localDate: Date
    let timeZoneIdentifier: String
    let currentManualMinutes: Int

    init(
        id: UUID = UUID(),
        localDate: Date,
        timeZoneIdentifier: String,
        currentManualMinutes: Int
    ) {
        self.id = id
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.currentManualMinutes = currentManualMinutes
    }
}

enum GamingManualAdjustmentDirection: String, CaseIterable, Identifiable {
    case add
    case remove

    var id: Self { self }

    var label: String {
        switch self {
        case .add: "Add time"
        case .remove: "Remove time"
        }
    }
}

struct GamingManualAdjustmentForm: Equatable {
    var direction: GamingManualAdjustmentDirection = .add
    var minutes = 15
    var note = ""
    let currentManualMinutes: Int

    var signedMinutes: Int? {
        guard (5...240).contains(minutes), minutes.isMultiple(of: 5) else {
            return nil
        }
        return direction == .add ? minutes : -minutes
    }

    var validationMessage: String? {
        guard (5...240).contains(minutes), minutes.isMultiple(of: 5) else {
            return "Choose 5 to 240 minutes in five-minute steps."
        }
        if direction == .add, currentManualMinutes > 1_440 - minutes {
            return currentManualMinutes >= 1_440
                ? "Today's manual allowance is already at the 1,440-minute maximum."
                : "You can add up to \(1_440 - currentManualMinutes) more manual minutes today."
        }
        if direction == .remove, minutes > currentManualMinutes {
            return "You can remove up to \(currentManualMinutes) manually granted minutes today."
        }
        guard note.trimmingCharacters(in: .whitespacesAndNewlines).count <= 160 else {
            return "Keep the optional note to 160 characters or fewer."
        }
        return nil
    }

    var canSubmit: Bool {
        validationMessage == nil
    }

    var normalizedNote: String? {
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
