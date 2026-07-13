import SwiftUI
import ZoidCoachCore

struct ActiveOfflineWorkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: ActiveOfflineWorkEntryController

    init(task: TodayTaskRow, controller: ActiveOfflineWorkEntryController? = nil) {
        _controller = StateObject(
            wrappedValue: controller ?? ActiveOfflineWorkEntryController(
                taskID: task.taskID,
                taskTitle: task.title
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AWAY-FROM-MAC WORK")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text("Record intentional work for \(controller.taskTitle)")
                .font(Sumi.display(26))
                .tracking(-0.6)
            Text("Use this only for work you actually completed away from this Mac. It counts toward actual task time, stays separate from Screenwatch-aligned time, and never turns missing telemetry into work.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker("Started", selection: $controller.startedAt, in: ...Date())
                .accessibilityIdentifier("active-offline-work.started")
            Stepper(
                "\(controller.durationMinutes) minutes",
                value: $controller.durationMinutes,
                in: ActiveOfflineWorkEntryController.minimumMinutes ... ActiveOfflineWorkEntryController.maximumMinutes,
                step: 5
            )
            .accessibilityLabel("Away-from-Mac work duration")
            .accessibilityValue("\(controller.durationMinutes) minutes")
            .accessibilityIdentifier("active-offline-work.duration")
            TextField("Optional note about what you completed", text: $controller.note)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("active-offline-work.note")

            if let error = controller.errorMessage {
                Text(error)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("active-offline-work.error")
            }
            if let success = controller.successMessage {
                Text(success)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.okay)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("active-offline-work.success")
            }

            HStack(spacing: 12) {
                Spacer()
                Button(controller.successMessage == nil ? "CANCEL" : "CLOSE") { dismiss() }
                    .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("active-offline-work.cancel")
                if controller.successMessage == nil {
                    Button(controller.isSaving ? "RECORDING" : "RECORD WORK") {
                        controller.save()
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                    .disabled(!controller.canSave)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("active-offline-work.save")
                }
            }
        }
        .padding(28)
        .frame(width: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-offline-work.sheet")
    }
}
