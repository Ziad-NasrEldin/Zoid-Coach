import SwiftUI

struct LocalTaskCreationView: View {
    @StateObject private var controller: LocalTaskCreationController
    let saved: () -> Void
    let cancel: () -> Void

    init(
        controller: @autoclosure @escaping () -> LocalTaskCreationController = LocalTaskCreationController(),
        saved: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        _controller = StateObject(wrappedValue: controller())
        self.saved = saved
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("LOCAL TASK")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Keep planning even when Apple Reminders is unavailable.")
                    .font(Sumi.display(24))
                    .tracking(-0.5)
                    .foregroundStyle(Sumi.ink)
                Text("This task stays on this Mac. It is never written to Apple Reminders unless you choose to recreate it there later.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Sumi.mist)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            VStack(alignment: .leading, spacing: 18) {
                SumiTextField("TASK TITLE", placeholder: "What needs to be done?", text: $controller.title)
                    .accessibilityIdentifier("local-task-title")
                    .disabled(controller.hasPendingRetry)
                SumiTextField("NOTES / OPTIONAL", placeholder: "Context you will need later", text: $controller.notes)
                    .accessibilityIdentifier("local-task-notes")
                    .disabled(controller.hasPendingRetry)
                SumiStepper(
                    "FOCUS ESTIMATE",
                    value: $controller.estimateMinutes,
                    in: 5...480,
                    step: 5,
                    valueLabel: { "\($0) MINUTES" }
                )
                .accessibilityIdentifier("local-task-estimate")
                .disabled(controller.hasPendingRetry)
                Toggle(isOn: $controller.addToToday) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ADD TO TODAY'S PLAN")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                        Text("Turn this off to keep the task in the unplanned inventory.")
                            .font(Sumi.body(12))
                            .foregroundStyle(Sumi.muted)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("local-task-add-to-today")
                .disabled(controller.hasPendingRetry)

                if let error = controller.errorMessage {
                    Text(error)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.sealDeep)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Sumi.sealWash)
                        .accessibilityIdentifier("local-task-error")
                }
            }
            .padding(24)

            HStack(spacing: 12) {
                Button("CANCEL", action: cancel)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        if await controller.save() { saved() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if controller.isSaving {
                            ProgressView().controlSize(.small).tint(Sumi.paper)
                        }
                        Text(controller.isSaving ? "SAVING" : (controller.hasPendingRetry ? "TRY AGAIN" : "CREATE LOCAL TASK"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .large))
                .disabled(!controller.canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("local-task-save")
            }
            .padding(24)
            .background(Sumi.softPaper)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .frame(width: 500)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
        .accessibilityIdentifier("local-task-sheet")
    }
}
