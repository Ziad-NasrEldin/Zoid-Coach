import SwiftUI

struct WakeTaskReconfirmationView: View {
    let confirmation: WakeTaskReconfirmation
    let continueTask: () -> Void
    let pauseTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("TASK CHECK-IN")
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)

            Text("Are you still working on this task?")
                .font(Sumi.display(30))
                .foregroundStyle(Sumi.ink)

            Text(confirmation.taskTitle)
                .font(Sumi.display(18))
                .foregroundStyle(Sumi.ink)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 8) {
                Label("This Mac was inactive for \(confirmation.durationLabel).", systemImage: "moon.zzz")
                Label("The task clock and observed activity are kept separate.", systemImage: "clock.badge.checkmark")
                Label("Time without telemetry is not counted as aligned work.", systemImage: "checkmark.shield")
            }
            .font(Sumi.body(13))
            .foregroundStyle(Sumi.muted)

            HStack(spacing: 12) {
                Button("PAUSE TASK") { pauseTask() }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("wake-task.pause")

                Spacer()

                Button("YES, CONTINUE") { continueTask() }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("wake-task.continue")
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(Sumi.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wake-task.confirmation")
    }
}

struct WakeTaskReconciliationNoticeView: View {
    let notice: WakeTaskReconciliationNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Sumi.okay)
            Text(notice.message)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .accessibilityLabel("Dismiss wake reconciliation")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 430)
        .background(Sumi.softPaper)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Sumi.rule, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wake-task.reconciliation-notice")
    }
}
