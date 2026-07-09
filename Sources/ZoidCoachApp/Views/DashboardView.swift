import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 218)

            Divider()

            ScrollView {
                Group {
                    if model.selectedSection == .today {
                        TodayCommandView()
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CommandHeaderView()
                            FoundationHeroView()
                            SourceHealthLedgerView()
                            LocalFoundationView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Sumi.paper)
        }
        .background(Sumi.paper)
        .preferredColorScheme(.light)
    }
}

private struct TodayCommandView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY / INBOX")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text("Real Apple Reminders")
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.muted)
                }

                Spacer()

                Button {
                    model.refreshReminderTasks()
                } label: {
                    HStack(spacing: 7) {
                        if model.isLoadingReminderTasks {
                            ProgressView().controlSize(.small).tint(Sumi.paper)
                        }
                        Text(model.isLoadingReminderTasks ? "LOADING" : "REFRESH TASKS")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                    }
                    .foregroundStyle(Sumi.paper)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Sumi.seal)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingReminderTasks)
                .accessibilityLabel("Refresh reminders")
            }
            .padding(.horizontal, 28)
            .frame(height: 72)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            VStack(alignment: .leading, spacing: 12) {
                Text("READY TO DECIDE")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Choose what matters\nbefore the day chooses for you.")
                    .font(Sumi.display(40))
                    .tracking(-1.2)
                    .foregroundStyle(Sumi.ink)
                Text("These are your incomplete Apple Reminders. Completing an item here marks the same reminder complete in Apple Reminders.")
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.muted)
                    .lineSpacing(4)
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 34)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("INCOMPLETE TASKS")
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                    Spacer()
                    Text("\(model.reminderTasks.count) AVAILABLE")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Sumi.mist)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

                if let error = model.reminderTaskError {
                    Text(error)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.seal)
                        .padding(28)
                } else if model.isLoadingReminderTasks && model.reminderTasks.isEmpty {
                    ProgressView("Loading your incomplete reminders")
                        .padding(28)
                } else if model.reminderTasks.isEmpty {
                    Text("No incomplete reminders are available. Connect Apple Reminders from Source health if access has not been granted.")
                        .font(Sumi.body(14))
                        .foregroundStyle(Sumi.muted)
                        .padding(28)
                } else {
                    ForEach(model.reminderTasks) { task in
                        ReminderTaskRow(task: task)
                    }
                }
            }
        }
    }
}

private struct ReminderTaskRow: View {
    @EnvironmentObject private var model: AppModel
    let task: ReminderTask

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.completeReminderTask(task)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Sumi.seal)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.ink)
                Text(task.listName)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }

            Spacer()

            if let dueLabel = task.dueLabel {
                Text(dueLabel.uppercased())
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
            }
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ZOID")
                    .font(Sumi.display(26))
                    .tracking(-0.8)
                Text("COACH / LOCAL COMMAND")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 30)

            Text("OPERATIONS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ForEach(AppSection.allCases) { section in
                Button {
                    model.selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 16)
                        Text(section.rawValue)
                            .font(Sumi.label(11))
                            .sumiLabelTracking()
                        Spacer()
                    }
                    .foregroundStyle(model.selectedSection == section ? Sumi.paper : Sumi.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(model.selectedSection == section ? Sumi.ink : Sumi.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Sumi.okay)
                        .frame(width: 7, height: 7)
                    Text("LOCAL ONLY")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }
                Text("Release 0 · Instrumented foundation")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.softPaper)
        }
        .background(Sumi.paper)
    }
}

private struct CommandHeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE HEALTH")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Instrumented foundation")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }

            Spacer()

            Text(model.coachingState.rawValue)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Sumi.ink)

            Button {
                model.runSourceCheck()
            } label: {
                HStack(spacing: 7) {
                    if model.isCheckingSources {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Sumi.paper)
                    }
                    Text(model.isCheckingSources ? "CHECKING" : "RUN SOURCE CHECK")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Sumi.seal)
            }
            .buttonStyle(.plain)
            .disabled(model.isCheckingSources)
            .accessibilityLabel("Run source check")
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sumi.rule).frame(height: 1)
        }
    }
}

private struct FoundationHeroView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                Text("RELEASE 0 / DAY ONE")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)

                Text("The command center\nis coming online.")
                    .font(Sumi.display(46))
                    .tracking(-1.5)
                    .foregroundStyle(Sumi.ink)

                Text("First we prove that intent, behavior, and intervention can share one reliable local state. Coaching remains in observation mode until the evidence is trustworthy.")
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.muted)
                    .lineSpacing(4)
                    .frame(maxWidth: 610, alignment: .leading)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Sumi.body(14))
                    .foregroundStyle(Sumi.ink)
                Text("CAIRO · LOCAL TIME")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 36)
        .background(Sumi.paper)
    }
}

private struct SourceHealthLedgerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SOURCE LEDGER")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                Spacer()
                Text(model.lastCheckAt.map { "Checked " + $0.formatted(date: .omitted, time: .shortened) } ?? "Awaiting first verified check")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Sumi.mist)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            ForEach(model.sources) { source in
                SourceHealthRow(source: source)
            }
        }
    }
}

private struct SourceHealthRow: View {
    @EnvironmentObject private var model: AppModel
    let source: SourceHealth

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(source.eyebrow)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(source.title)
                    .font(Sumi.display(20))
            }
            .frame(width: 185, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.detail)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.ink)
                Text(source.evidence)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }

            Spacer()

            HealthBadge(state: source.state)

            Button(source.actionTitle.uppercased()) {
                model.checkSource(source.id)
            }
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .buttonStyle(.plain)
                .foregroundStyle(Sumi.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityLabel(source.actionTitle + " " + source.title)
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 82)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sumi.paleRule).frame(height: 1)
        }
    }
}

private struct HealthBadge: View {
    let state: HealthState

    var body: some View {
        Text(state.rawValue)
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(background)
            .overlay { Rectangle().stroke(border, lineWidth: 1) }
            .accessibilityLabel("Status " + state.rawValue)
    }

    private var background: Color {
        switch state.tone {
        case .okay: Sumi.okay
        case .ink: Sumi.ink
        case .seal: Sumi.seal
        case .muted: Sumi.mist
        }
    }

    private var foreground: Color {
        state.tone == .muted ? Sumi.muted : Sumi.paper
    }

    private var border: Color {
        state.tone == .muted ? Sumi.rule : background
    }
}

private struct LocalFoundationView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FoundationColumn(
                index: "01",
                title: "Local event store",
                copy: "Immutable source and domain events will make every state transition replayable and explainable.",
                state: "NEXT"
            )

            Divider()

            FoundationColumn(
                index: "02",
                title: "Rules before models",
                copy: "Release 1 will classify known work and gaming contexts without a remote or local model dependency.",
                state: "DECIDED"
            )

            Divider()

            FoundationColumn(
                index: "03",
                title: "Seven quiet days",
                copy: "Behavior is observed for one complete week before accountability prompts are allowed.",
                state: "LOCKED"
            )
        }
        .background(Sumi.softPaper)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }
}

private struct FoundationColumn: View {
    let index: String
    let title: String
    let copy: String
    let state: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(index)
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Spacer()
                Text(state)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            Text(title)
                .font(Sumi.display(19))
            Text(copy)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
    }
}
