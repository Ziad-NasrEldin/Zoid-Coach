import SwiftUI
import ZoidCoachCore

enum LearnedEstimateDecision: Equatable {
    case undecided
    case used(Int)
    case keptOriginal
}

struct LearnedEstimateSuggestionPresentation: Equatable {
    let suggestion: LearnedEstimateSuggestion
    let currentEstimateMinutes: Int?

    var confidenceLabel: String {
        suggestion.hasLimitedEvidence ? "EARLY PATTERN" : "ESTABLISHED PATTERN"
    }

    var evidenceText: String {
        let taskWord = suggestion.sampleCount == 1 ? "task" : "tasks"
        return "Based on \(suggestion.sampleCount) similar completed \(taskWord). Actual aligned work ranged from \(suggestion.minimumActualMinutes) to \(suggestion.maximumActualMinutes) minutes."
    }

    var keepLabel: String {
        currentEstimateMinutes.map { "KEEP \($0) MIN" } ?? "KEEP UNKNOWN"
    }

    func statusText(for decision: LearnedEstimateDecision) -> String? {
        switch decision {
        case .undecided:
            nil
        case let .used(minutes):
            "USED \(minutes) MIN - YOU CAN STILL CHOOSE A DIFFERENT ESTIMATE"
        case .keptOriginal:
            currentEstimateMinutes.map { "KEPT YOUR \($0) MIN ESTIMATE" } ?? "KEPT ESTIMATE AS UNKNOWN"
        }
    }
}

struct LearnedEstimateSuggestionView: View {
    let taskID: String
    let taskTitle: String
    let suggestion: LearnedEstimateSuggestion
    let currentEstimateMinutes: Int?
    let useSuggestion: (Int) -> Void
    @State private var decision: LearnedEstimateDecision = .undecided

    private var presentation: LearnedEstimateSuggestionPresentation {
        LearnedEstimateSuggestionPresentation(
            suggestion: suggestion,
            currentEstimateMinutes: currentEstimateMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("LEARNED ESTIMATE")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(presentation.confidenceLabel)
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
                    .foregroundStyle(suggestion.hasLimitedEvidence ? Sumi.muted : Sumi.okay)
            }
            Text("Zoid 666 suggests \(suggestion.recommendedMinutes) minutes for \(taskTitle).")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.ink)
            Text(presentation.evidenceText)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Advisory only. Your estimate does not change until you choose Use.")
                .font(Sumi.body(10))
                .foregroundStyle(Sumi.muted)
            if let status = presentation.statusText(for: decision) {
                Text(status)
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                    .accessibilityIdentifier("today.estimate-learning.\(taskID).status")
            } else {
                HStack(spacing: 10) {
                    Button("USE \(suggestion.recommendedMinutes) MIN") {
                        useSuggestion(suggestion.recommendedMinutes)
                        decision = .used(suggestion.recommendedMinutes)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                    .accessibilityIdentifier("today.estimate-learning.\(taskID).use")
                    Button(presentation.keepLabel) {
                        decision = .keptOriginal
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityIdentifier("today.estimate-learning.\(taskID).keep")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.softPaper)
        .overlay { Rectangle().stroke(Sumi.paleRule, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.estimate-learning.\(taskID)")
    }
}
