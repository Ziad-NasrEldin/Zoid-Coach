import SwiftUI
import ZoidCoachCore

struct TodayDayStatePresentation: Equatable {
    enum Kind: Equatable {
        case preparing
        case active
        case planned
        case planning
        case invitation
        case snoozed
        case dismissed
        case unplanned
        case open
    }

    let kind: Kind
    let title: String
    let detail: String

    static func resolve(snapshot: TodaySnapshot) -> TodayDayStatePresentation {
        resolve(
            snapshotIsAvailable: true,
            planningMode: snapshot.planningStatus?.mode,
            hasActiveTask: snapshot.activeTask != nil,
            hasPlannedTasks: !snapshot.taskRows.isEmpty || snapshot.mainObjective != nil
        )
    }

    static func resolve(
        snapshotIsAvailable: Bool,
        planningMode: PlanningDayMode?,
        hasActiveTask: Bool,
        hasPlannedTasks: Bool
    ) -> TodayDayStatePresentation {
        guard snapshotIsAvailable else {
            return .init(
                kind: .preparing,
                title: "PREPARING TODAY",
                detail: "Local sources are still preparing the current day."
            )
        }
        if hasActiveTask {
            return .init(
                kind: .active,
                title: "ACTIVE WORK",
                detail: "One task is currently tracking time."
            )
        }
        switch planningMode {
        case .invitation:
            return .init(
                kind: .invitation,
                title: "PLAN NEEDED",
                detail: "No plan has been approved for today."
            )
        case .snoozed:
            return .init(
                kind: .snoozed,
                title: "PLANNING SNOOZED",
                detail: "The planning invitation will return later."
            )
        case .dismissed:
            return .init(
                kind: .dismissed,
                title: "PLANNING DISMISSED",
                detail: "Planning is available whenever you want to return."
            )
        case .unplanned:
            return .init(
                kind: .unplanned,
                title: "UNPLANNED DAY",
                detail: "Tasks remain available without an approved plan."
            )
        case .planning:
            if hasPlannedTasks {
                return .init(
                    kind: .planned,
                    title: "PLANNED DAY",
                    detail: "Today's commitments are ready."
                )
            }
            return .init(
                kind: .planning,
                title: "PLANNING",
                detail: "Today's commitments are being prepared."
            )
        case nil:
            if hasPlannedTasks {
                return .init(
                    kind: .planned,
                    title: "PLANNED DAY",
                    detail: "Today's commitments are ready."
                )
            }
            return .init(
                kind: .open,
                title: "OPEN DAY",
                detail: "No active task or plan is currently recorded."
            )
        }
    }
}

struct TodayDayStateHeader: View {
    let date: Date
    let presentation: TodayDayStatePresentation

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY / ONE DELIBERATE MOVE")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(formattedDate)
                    .font(Sumi.display(30))
                    .foregroundStyle(Sumi.ink)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 5) {
                Text("DAY STATE")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                Text(presentation.title)
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(presentation.detail)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(formattedDate). Day state: \(presentation.title). \(presentation.detail)")
        .accessibilityIdentifier("today.day-state")
    }

    private var formattedDate: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
