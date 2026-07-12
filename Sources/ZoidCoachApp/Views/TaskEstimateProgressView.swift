import SwiftUI
import ZoidCoachCore

struct TaskEstimateProgressView: View {
    let progress: TaskEstimateProgress
    var compact = false
    var isRunning = false
    let identifier: String
    @State private var renderedAt = Date()

    var body: some View {
        TimelineView(.periodic(from: renderedAt, by: 60)) { context in
            content(for: currentProgress(at: context.date))
        }
    }

    private func content(for progress: TaskEstimateProgress) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.elapsedMinutes) MIN TRACKED")
                    .font(Sumi.label(compact ? 8 : 9))
                    .sumiLabelTracking()
                Spacer(minLength: 8)
                Text("\(progress.estimateMinutes) MIN ESTIMATE")
                    .font(Sumi.label(compact ? 8 : 9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Sumi.paleRule)
                    Rectangle()
                        .fill(progress.phase == .overEstimate ? Sumi.sealDeep : Sumi.ink)
                        .frame(width: geometry.size.width * progress.boundedFraction)
                }
            }
            .frame(height: compact ? 3 : 5)
            HStack {
                Text(progress.statusLabel)
                    .font(Sumi.body(compact ? 10 : 11))
                    .foregroundStyle(progress.phase == .overEstimate ? Sumi.sealDeep : Sumi.muted)
                Spacer(minLength: 8)
                Text("\(progress.percent)%")
                    .font(Sumi.body(compact ? 10 : 11))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.accessibilitySummary)
        .accessibilityIdentifier(identifier)
    }

    private func currentProgress(at date: Date) -> TaskEstimateProgress {
        guard isRunning else { return progress }
        let additionalMinutes = Int(max(0, date.timeIntervalSince(renderedAt)) / 60)
        return progress.addingElapsedMinutes(additionalMinutes)
    }
}
