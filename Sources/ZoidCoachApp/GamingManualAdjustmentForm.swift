import Foundation

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

    var signedMinutes: Int {
        direction == .add ? minutes : -minutes
    }

    var validationMessage: String? {
        guard (5...240).contains(minutes), minutes.isMultiple(of: 5) else {
            return "Choose 5 to 240 minutes in five-minute steps."
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
