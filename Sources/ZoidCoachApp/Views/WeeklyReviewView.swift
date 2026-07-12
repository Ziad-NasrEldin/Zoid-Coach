import Foundation
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol WeeklyReviewServicing: AnyObject {
    func load(referenceDate: Date?) throws -> WeeklyReviewSnapshot
    func acceptExperiment(id: String) throws -> WeeklyExperiment
    func rejectExperiment(id: String) throws -> WeeklyExperiment
    func editExperiment(id: String, title: String, instruction: String, measurement: String) throws -> WeeklyExperiment
}

extension WeeklyReviewStore: WeeklyReviewServicing {}

@MainActor
final class WeeklyReviewController: ObservableObject {
    @Published private(set) var snapshot: WeeklyReviewSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published var isEditingExperiment = false
    @Published var editTitle = ""
    @Published var editInstruction = ""
    @Published var editMeasurement = ""

    private let service: WeeklyReviewServicing

    init(service: WeeklyReviewServicing) {
        self.service = service
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        do {
            try self.init(service: WeeklyReviewStore(databaseURL: runtimeEnvironment.databaseURL))
        } catch {
            self.init(service: UnavailableWeeklyReviewService(error: error))
            errorMessage = error.localizedDescription
        }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try service.load(referenceDate: nil)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        guard let experiment = snapshot?.experiment else { return }
        editTitle = experiment.title
        editInstruction = experiment.instruction
        editMeasurement = experiment.measurement
        isEditingExperiment = true
        errorMessage = nil
    }

    func cancelEditing() {
        isEditingExperiment = false
        errorMessage = nil
    }

    func saveExperiment() {
        guard let id = snapshot?.experiment?.id else { return }
        mutate(success: "Experiment updated. Review and accept it when it feels realistic.") {
            try service.editExperiment(
                id: id,
                title: editTitle,
                instruction: editInstruction,
                measurement: editMeasurement
            )
        }
        if errorMessage == nil { isEditingExperiment = false }
    }

    func acceptExperiment() {
        guard let id = snapshot?.experiment?.id else { return }
        mutate(success: "Experiment accepted. Zoid 666 will keep its next-week tracking visible here.") {
            try service.acceptExperiment(id: id)
        }
    }

    func rejectExperiment() {
        guard let id = snapshot?.experiment?.id else { return }
        mutate(success: "Experiment rejected. No experiment will be treated as active.") {
            try service.rejectExperiment(id: id)
        }
    }

    private func mutate(success: String, operation: () throws -> WeeklyExperiment) {
        do {
            _ = try operation()
            snapshot = try service.load(referenceDate: nil)
            successMessage = success
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

private final class UnavailableWeeklyReviewService: WeeklyReviewServicing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func load(referenceDate: Date?) throws -> WeeklyReviewSnapshot { throw error }
    func acceptExperiment(id: String) throws -> WeeklyExperiment { throw error }
    func rejectExperiment(id: String) throws -> WeeklyExperiment { throw error }
    func editExperiment(id: String, title: String, instruction: String, measurement: String) throws -> WeeklyExperiment { throw error }
}

struct WeeklyReviewView: View {
    @StateObject private var controller: WeeklyReviewController

    init(controller: WeeklyReviewController? = nil) {
        _controller = StateObject(wrappedValue: controller ?? WeeklyReviewController())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if controller.isLoading {
                ProgressView("Building the local weekly review...")
                    .accessibilityIdentifier("reviews.weekly.loading")
            } else if let message = controller.errorMessage {
                statusCard(title: "WEEKLY REVIEW UNAVAILABLE", message: message, isError: true)
            } else if let snapshot = controller.snapshot {
                quality(snapshot)
                outcomes(snapshot.outcomes)
                patterns(snapshot)
                experiment(snapshot)
            }

            if let success = controller.successMessage {
                Text(success)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.okay)
                    .accessibilityIdentifier("reviews.weekly.success")
            }
        }
        .task { controller.load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.weekly")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WEEKLY REVIEW")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Spacer()
                Button("REFRESH") { controller.load() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityIdentifier("reviews.weekly.refresh")
            }
            Text("Patterns need evidence, not certainty theater.")
                .font(Sumi.display(28))
                .tracking(-0.8)
            Text("Seven local days are summarized below. Corrections from Daily Review are respected, examples stay privacy-safe, and every conclusion shows its sample size and an alternative explanation.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
        }
    }

    private func quality(_ snapshot: WeeklyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.quality == .sufficient ? "ENOUGH COVERAGE" : "DATA QUALITY SUMMARY")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                Spacer()
                Text("\(snapshot.coveredDays)/\(snapshot.totalDays) DAYS")
                    .font(.system(size: 12, design: .monospaced))
            }
            Text(snapshot.qualityExplanation)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
            Text("\(snapshot.dateRange.startDay) TO \(snapshot.dateRange.endDay)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Sumi.muted)
        }
        .padding(16)
        .background(snapshot.quality == .sufficient ? Sumi.wash : Sumi.sealWash)
        .overlay(Rectangle().stroke(snapshot.quality == .sufficient ? Sumi.rule : Sumi.seal, lineWidth: 1))
        .accessibilityIdentifier("reviews.weekly.quality")
    }

    private func outcomes(_ summary: WeeklyReviewOutcomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLANNED VS COMPLETED")
                .font(Sumi.label())
                .sumiLabelTracking()
            HStack(spacing: 12) {
                metric("PLANNED", value: "\(summary.plannedTasks)", detail: "\(summary.plannedMinutes) estimated min")
                metric("COMPLETED", value: "\(summary.completedTasks)", detail: "Confirmed plan items")
                metric("OUTCOME RATE", value: "\(summary.completedPercent)%", detail: "Not a productivity score")
            }
        }
        .accessibilityIdentifier("reviews.weekly.outcomes")
    }

    private func metric(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Sumi.label()).sumiLabelTracking().foregroundStyle(Sumi.muted)
            Text(value).font(Sumi.display(24))
            Text(detail).font(Sumi.body(11)).foregroundStyle(Sumi.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.paper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
    }

    @ViewBuilder
    private func patterns(_ snapshot: WeeklyReviewSnapshot) -> some View {
        if snapshot.quality == .limited {
            statusCard(
                title: "NO STRONG CONCLUSIONS YET",
                message: "Zoid 666 will not turn one or two days into a habit claim. Confirm at least three adequately observed daily reviews first.",
                isError: false
            )
        } else if snapshot.patterns.isEmpty {
            statusCard(
                title: "NO REPEATED PATTERN FOUND",
                message: "Coverage is sufficient, but the evidence does not support a repeated estimate, work-window, drift, gaming, prompt, or blocked-task pattern.",
                isError: false
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("EVIDENCE-BACKED PATTERNS")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                ForEach(snapshot.patterns) { pattern in
                    WeeklyPatternCard(pattern: pattern)
                }
            }
            .accessibilityIdentifier("reviews.weekly.patterns")
        }
    }

    @ViewBuilder
    private func experiment(_ snapshot: WeeklyReviewSnapshot) -> some View {
        if let experiment = snapshot.experiment {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ONE EXPERIMENT FOR NEXT WEEK")
                        .font(Sumi.label())
                        .sumiLabelTracking()
                    Spacer()
                    Text(experiment.state.rawValue.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(experiment.state == .accepted ? Sumi.okay : Sumi.muted)
                }

                if controller.isEditingExperiment {
                    TextField("Experiment title", text: $controller.editTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reviews.weekly.experiment.title")
                    TextField("One concrete action", text: $controller.editInstruction, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reviews.weekly.experiment.instruction")
                    TextField("How to measure it", text: $controller.editMeasurement, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reviews.weekly.experiment.measurement")
                    HStack {
                        Button("SAVE EDIT") { controller.saveExperiment() }
                            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                            .accessibilityIdentifier("reviews.weekly.experiment.save")
                        Button("CANCEL") { controller.cancelEditing() }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    }
                } else {
                    Text(experiment.title).font(Sumi.display(23))
                    Text(experiment.instruction).font(Sumi.body(13))
                    Text("MEASURE · \(experiment.measurement)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Sumi.muted)

                    if experiment.state == .accepted {
                        Text("TRACKING \(experiment.trackingDaysCompleted)/7 DAYS · START \(experiment.trackingWeekStart ?? "NEXT WEEK")")
                            .font(Sumi.label())
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.okay)
                            .accessibilityIdentifier("reviews.weekly.experiment.tracking")
                    }

                    HStack {
                        Button("ACCEPT") { controller.acceptExperiment() }
                            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                            .disabled(experiment.state == .accepted)
                            .accessibilityIdentifier("reviews.weekly.experiment.accept")
                        Button("EDIT") { controller.beginEditing() }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                            .accessibilityIdentifier("reviews.weekly.experiment.edit")
                        Button("REJECT") { controller.rejectExperiment() }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                            .disabled(experiment.state == .rejected)
                            .accessibilityIdentifier("reviews.weekly.experiment.reject")
                    }
                }
            }
            .padding(18)
            .background(Sumi.wash)
            .overlay(Rectangle().stroke(Sumi.ink, lineWidth: 1))
            .accessibilityIdentifier("reviews.weekly.experiment")
        } else if snapshot.quality == .sufficient {
            statusCard(
                title: "NO EXPERIMENT RECOMMENDED",
                message: "The available patterns are not strong enough to justify changing next week. Zoid 666 will keep observing locally.",
                isError: false
            )
        }
    }

    private func statusCard(title: String, message: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Sumi.label()).sumiLabelTracking()
            Text(message).font(Sumi.body(13)).foregroundStyle(Sumi.muted)
        }
        .padding(16)
        .background(isError ? Sumi.seal.opacity(0.08) : Sumi.paper)
        .overlay(Rectangle().stroke(isError ? Sumi.seal : Sumi.rule, lineWidth: 1))
        .accessibilityIdentifier(isError ? "reviews.weekly.error" : "reviews.weekly.empty")
    }
}

private struct WeeklyPatternCard: View {
    let pattern: WeeklyReviewPattern
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pattern.title.uppercased())
                    .font(Sumi.label())
                    .sumiLabelTracking()
                Spacer()
                Text("\(pattern.confidencePercent)% CONFIDENCE")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Sumi.muted)
            }
            Text(pattern.conclusion).font(Sumi.body(14))
            Text("\(pattern.sampleCount) SAMPLES · \(pattern.dateRange.startDay) TO \(pattern.dateRange.endDay)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Sumi.muted)
            Button(showsEvidence ? "HIDE EVIDENCE" : "SHOW EVIDENCE") {
                showsEvidence.toggle()
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .accessibilityIdentifier("reviews.weekly.pattern.\(pattern.id).evidence")

            if showsEvidence {
                ForEach(pattern.examples, id: \.self) { example in
                    Text("• \(example)").font(Sumi.body(12)).foregroundStyle(Sumi.muted)
                }
                Text("ALTERNATIVE · \(pattern.alternativeExplanation)")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .padding(16)
        .background(Sumi.paper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.weekly.pattern.\(pattern.id)")
    }
}
