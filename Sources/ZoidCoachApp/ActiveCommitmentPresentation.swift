import Foundation
import ZoidCoachCore

struct ActiveCommitmentPresentation: Equatable {
    enum TimingMode: Equatable {
        case openEnded
        case bounded(durationMinutes: Int, remainingMinutes: Int)
        case continuedOpenEnded
        case sprintComplete
    }

    let taskTitle: String
    let elapsedMinutes: Int
    let timingMode: TimingMode

    init?(task: TodayTaskRow, at date: Date = Date()) {
        guard task.state == .active else { return nil }
        taskTitle = task.title
        elapsedMinutes = task.elapsedMinutes
        switch task.sprint?.state {
        case .active:
            guard let sprint = task.sprint else { return nil }
            timingMode = .bounded(
                durationMinutes: sprint.durationMinutes,
                remainingMinutes: max(0, (sprint.remainingSeconds(at: date) + 59) / 60)
            )
        case .continuedOpenEnded:
            timingMode = .continuedOpenEnded
        case .expired:
            timingMode = .sprintComplete
        case .paused, .finished, .none:
            timingMode = .openEnded
        }
    }

    var modeLabel: String {
        switch timingMode {
        case .openEnded: "OPEN-ENDED SESSION"
        case let .bounded(durationMinutes, _): "\(durationMinutes)-MINUTE SPRINT"
        case .continuedOpenEnded: "OPEN-ENDED CONTINUATION"
        case .sprintComplete: "SPRINT COMPLETE"
        }
    }

    var dashboardHeading: String {
        switch timingMode {
        case .openEnded, .continuedOpenEnded:
            "ACTIVE COMMITMENT · OPEN-ENDED · \(elapsedMinutes) MIN TRACKED"
        case let .bounded(_, remainingMinutes):
            "ACTIVE COMMITMENT · \(remainingMinutes) MIN LEFT · \(elapsedMinutes) MIN TRACKED"
        case .sprintComplete:
            "ACTIVE COMMITMENT · SPRINT COMPLETE · \(elapsedMinutes) MIN TRACKED"
        }
    }

    var detail: String {
        switch timingMode {
        case .openEnded:
            "Manual tracking continues until you choose Pause or Complete. No automatic end time is implied."
        case let .bounded(durationMinutes, remainingMinutes):
            "This is a bounded \(durationMinutes)-minute sprint with about \(remainingMinutes) minutes left. The task stays incomplete when the boundary arrives."
        case .continuedOpenEnded:
            "The sprint boundary passed and manual tracking is continuing without an automatic end time. Choose Pause or Complete when the state changes."
        case .sprintComplete:
            "The sprint boundary has arrived. The task is still incomplete until you continue, pause, or complete it deliberately."
        }
    }

    var menuStatus: String {
        switch timingMode {
        case .openEnded:
            "Active · Open-ended · \(elapsedMinutes) min tracked"
        case let .bounded(_, remainingMinutes):
            "Active sprint · \(remainingMinutes) min left · \(elapsedMinutes) min tracked"
        case .continuedOpenEnded:
            "Active · Open-ended continuation · \(elapsedMinutes) min tracked"
        case .sprintComplete:
            "Sprint complete · Task remains active"
        }
    }

    var accessibilitySummary: String {
        "\(taskTitle). \(modeLabel). \(elapsedMinutes) minutes tracked. \(detail)"
    }
}
