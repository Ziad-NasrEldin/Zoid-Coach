import SwiftUI

struct CalendarPlanApprovalSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch model.calendarPlanApproval.writeState {
            case .reviewing, .queueing:
                preview
            case let .pending(commandIDs):
                resultPanel(
                    eyebrow: "CALENDAR WRITE IN PROGRESS",
                    title: "Your plan is accepted",
                    detail: "Zoid 666 queued \(commandIDs.count) exact Calendar and Reminder change\(commandIDs.count == 1 ? "" : "s"). Keep this panel open to recheck, or close it and continue working while the local agent finishes.",
                    symbol: "clock.arrow.circlepath"
                )
            case let .applied(commandCount):
                resultPanel(
                    eyebrow: "CALENDAR CONFIRMED",
                    title: "Today is reserved",
                    detail: commandCount == 0
                        ? "The accepted plan already matched the configured Calendar and Reminders. No duplicate changes were created."
                        : "The local agent confirmed \(commandCount) Calendar and Reminder change\(commandCount == 1 ? "" : "s"). Your approved day is now durable.",
                    symbol: "checkmark.circle.fill"
                )
            case let .failed(commandIDs):
                resultPanel(
                    eyebrow: "CALENDAR NEEDS ATTENTION",
                    title: "Your plan is safe, but some writes failed",
                    detail: "\(commandIDs.count) change\(commandIDs.count == 1 ? "" : "s") could not be applied. The plan remains saved locally. Open Source Health to repair Calendar access, then recheck here. Zoid 666 will not claim that the blocks exist until the agent confirms them.",
                    symbol: "exclamationmark.triangle.fill"
                )
            case .idle:
                EmptyView()
            }
            if showsRestoredReceipt, let receipt = model.calendarPlanApproval.receipt {
                receiptDetails(receipt)
            }
        }
        .frame(width: 560)
        .background(Sumi.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-plan-approval-sheet")
    }

    private var showsRestoredReceipt: Bool {
        switch model.calendarPlanApproval.writeState {
        case .pending, .applied, .failed:
            true
        case .idle, .reviewing, .queueing:
            false
        }
    }

    private func receiptDetails(_ receipt: CalendarPlanApprovalReceipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPROVED \(receipt.approvedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            ForEach(receipt.items) { item in
                HStack {
                    Text("\(item.rank). \(item.title)\(item.isMainObjective ? " · MAIN" : "")")
                    Spacer()
                    Text(item.estimateIsUncertain == true ? "~\(item.estimateMinutes)m placeholder" : "\(item.estimateMinutes)m")
                }
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.ink)
            }
        }
        .padding(18)
        .background(Sumi.wash)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-plan-approval-receipt-details")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PLAN APPROVAL")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Review before Zoid 666 writes")
                    .font(Sumi.display(28))
                    .tracking(-0.5)
                    .foregroundStyle(Sumi.ink)
            }
            Spacer()
            Button("CLOSE", action: model.dismissCalendarPlanApproval)
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .disabled(model.isSchedulingDailyPlan)
        }
        .padding(24)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                metric("PLANNED", model.calendarPlanApproval.plannedMinutes)
                metric("AVAILABLE", model.calendarPlanApproval.availableMinutes)
                metric("CALENDAR BUSY", model.calendarPlanApproval.fixedCommitmentMinutes)
                metric("UNALLOCATED", model.calendarPlanApproval.remainingMinutes)
            }
            .background(Sumi.softPaper)

            Text(model.calendarPlanApproval.usesCalendarAvailability
                 ? "Existing Calendar commitments are already excluded. Exact work-block times are selected inside your configured work windows when you confirm."
                 : "Calendar availability could not be read, so this preview uses configured work windows only. Repair Calendar access before confirming if you need conflict-aware placement.")
                .font(Sumi.body(12))
                .foregroundStyle(model.calendarPlanApproval.usesCalendarAvailability ? Sumi.muted : Sumi.sealDeep)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(model.calendarPlanApproval.usesCalendarAvailability ? Sumi.paper : Sumi.sealWash)

            if let error = model.calendarScheduleError {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NOTHING WAS WRITTEN")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text(error)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("REVIEW UPDATED AVAILABILITY") {
                            model.requestCalendarPlanApproval()
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .compact))
                        .accessibilityHint("Reads Calendar availability again and replaces this preview without changing the current plan.")
                        .accessibilityIdentifier("calendar-plan-review-updated-availability")

                        Button("OPEN SOURCE HEALTH") {
                            model.selectedSection = .diagnostics
                            model.dismissCalendarPlanApproval()
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityIdentifier("calendar-plan-open-source-health")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.sealWash)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-plan-write-refusal")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.calendarPlanApproval.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", item.rank))
                                .font(Sumi.label(9))
                                .foregroundStyle(Sumi.seal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(Sumi.body(13))
                                    .foregroundStyle(Sumi.ink)
                                    .lineLimit(2)
                                if item.isMainObjective {
                                    Text("MAIN OBJECTIVE")
                                        .font(Sumi.label(8))
                                        .sumiLabelTracking()
                                        .foregroundStyle(Sumi.seal)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.estimateIsUncertain == true ? "~\(item.estimateMinutes) MIN" : "\(item.estimateMinutes) MIN")
                                    .font(Sumi.label(9))
                                    .sumiLabelTracking()
                                if item.estimateIsUncertain == true {
                                    Text("UNCERTAIN PLACEHOLDER")
                                        .font(Sumi.label(7))
                                        .sumiLabelTracking()
                                }
                            }
                            .foregroundStyle(item.estimateIsUncertain == true ? Sumi.seal : Sumi.muted)
                            .accessibilityLabel(item.estimateIsUncertain == true
                                ? "Unknown estimate using a conservative \(item.estimateMinutes) minute placeholder"
                                : "\(item.estimateMinutes) minute estimate")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
                    }
                }
            }
            .frame(maxHeight: 280)
            .accessibilityIdentifier("calendar-plan-reviewed-items")

            HStack {
                Button("GO BACK", action: model.dismissCalendarPlanApproval)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(model.isSchedulingDailyPlan)
                Spacer()
                Button(model.isSchedulingDailyPlan ? "QUEUING" : "CONFIRM AND WRITE") {
                    model.scheduleDailyPlan()
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(model.isSchedulingDailyPlan)
                .accessibilityHint("Queues only the reviewed work blocks and related Reminder updates through the local agent.")
                .accessibilityIdentifier("calendar-plan-confirm-write")
            }
            .padding(20)
        }
    }

    private func resultPanel(eyebrow: String, title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Sumi.seal)
            Text(eyebrow)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(title)
                .font(Sumi.display(24))
                .foregroundStyle(Sumi.ink)
            Text(detail)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("OPEN SOURCE HEALTH") {
                    model.selectedSection = .diagnostics
                    model.dismissCalendarPlanApproval()
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                Spacer()
                if case .failed = model.calendarPlanApproval.writeState {
                    Button("RETRY FAILED CHANGES", action: model.retryCalendarPlanWrite)
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                        .accessibilityIdentifier("calendar-plan-approval.retry-failed")
                } else {
                    Button("RECHECK", action: model.recheckCalendarPlanWrite)
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                }
                Button("DONE", action: model.dismissCalendarPlanApproval)
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
            }
        }
        .padding(24)
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)m")
                .font(Sumi.display(20))
                .foregroundStyle(Sumi.ink)
            Text(label)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Sumi.rule).frame(width: 1) }
    }
}
