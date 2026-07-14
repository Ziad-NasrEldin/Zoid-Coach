import SwiftUI
import ZoidCoachCore

struct BehaviorEvidenceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let snapshot: TodaySnapshot

    private var evidence: BehaviorEvidenceState {
        BehaviorEvidenceState(snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    categoryLedger
                    workCategoryLedger
                    uncertaintyCard
                    coverageCard
                }
                .padding(22)
            }
            actions
        }
        .frame(width: 660, height: 540)
        .background(Sumi.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.behavior-evidence.sheet")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BEHAVIOR EVIDENCE")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("What Zoid 666 observed today")
                    .font(Sumi.display(26))
                    .tracking(-0.4)
                Text("Local classifications and source limits, separated from assumptions about intent.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
            Spacer()
            Button("CLOSE", action: dismiss.callAsFunction)
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .accessibilityIdentifier("today.behavior-evidence.close")
        }
        .padding(22)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private var categoryLedger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BEHAVIOR TOTALS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            HStack(spacing: 0) {
                ForEach(evidence.categories) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(category.minutes)m")
                            .font(Sumi.display(20))
                        Text(category.title.uppercased())
                            .font(Sumi.label(7))
                            .sumiLabelTracking()
                            .foregroundStyle(category.classification == .unknown ? Sumi.seal : Sumi.muted)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(category.title), \(category.minutes) minutes")
                    .accessibilityIdentifier("today.behavior-evidence.category.\(category.classification.rawValue)")
                }
            }
            ForEach(evidence.categories) { category in
                HStack(alignment: .top, spacing: 10) {
                    Text(category.title.uppercased())
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .frame(width: 100, alignment: .leading)
                    Text(category.explanation)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("today.behavior-evidence.categories")
    }

    private var workCategoryLedger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORK CATEGORIES")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            Text(evidence.workCategoryDetail)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(evidence.workCategories) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(category.minutes)m")
                            .font(Sumi.display(18))
                        Text(category.title.uppercased())
                            .font(Sumi.label(7))
                            .sumiLabelTracking()
                            .foregroundStyle(category.category == .uncategorized ? Sumi.seal : Sumi.muted)
                        Text(category.explanation)
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(category.accessibilityLabel)
                    .accessibilityHint(category.explanation)
                    .accessibilityIdentifier(category.accessibilityIdentifier)
                }
            }
        }
        .accessibilityIdentifier("today.behavior-evidence.work-categories")
    }

    private var uncertaintyCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(evidence.unknownMinutes > 0 ? "ZOID 666 MAY BE WRONG HERE" : "NO UNKNOWN TIME OBSERVED")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(evidence.unknownMinutes > 0 ? Sumi.seal : Sumi.muted)
            Text(evidence.unknownMinutes > 0
                 ? "\(evidence.unknownMinutes) minutes remain Unknown. They are not counted as distraction or used as strong drift evidence. Review the sessions if you know what they were."
                 : "Nothing is currently waiting for classification correction. You can still review observed sessions before confirming the day.")
                .font(Sumi.body(12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(evidence.unknownMinutes > 0 ? Sumi.sealWash : Sumi.softPaper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.behavior-evidence.uncertainty")
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(evidence.coverageTitle)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(evidence.hasSourceIssue ? Sumi.seal : Sumi.muted)
            Text(evidence.coverageDetail)
                .font(Sumi.body(12))
                .fixedSize(horizontal: false, vertical: true)
            if let source = evidence.sourceIssueTitle, let detail = evidence.sourceIssueDetail {
                Text("\(source): \(detail)")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.behavior-evidence.coverage")
    }

    private var actions: some View {
        HStack {
            Button("OPEN SOURCE HEALTH") {
                model.selectedSection = .diagnostics
                dismiss()
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
            .accessibilityIdentifier("today.behavior-evidence.open-source-health")
            Spacer()
            Button("REVIEW AND CORRECT ACTIVITY") {
                model.selectedSection = .reviews
                dismiss()
            }
            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
            .accessibilityIdentifier("today.behavior-evidence.review-correct")
            Button("DONE", action: dismiss.callAsFunction)
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
        }
        .padding(18)
        .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }
}
