import SwiftUI
import ZoidCoachCore

enum TaskKeyboardAction: Equatable {
    case start(taskID: String, title: String)
    case pause(taskID: String, title: String)
    case resume(taskID: String, title: String)

    var command: TaskActivityCommand {
        switch self {
        case .start: .start
        case .pause: .pauseDoneForNow
        case .resume: .resume
        }
    }

    var taskID: String {
        switch self {
        case let .start(taskID, _), let .pause(taskID, _), let .resume(taskID, _): taskID
        }
    }
}

struct TaskKeyboardCommandState: Equatable {
    let startAction: TaskKeyboardAction?
    let lifecycleAction: TaskKeyboardAction?

    init(
        snapshot: TodaySnapshot?,
        commandIsPending: Bool,
        commandsAreAvailable: Bool = true
    ) {
        guard commandsAreAvailable, !commandIsPending, let snapshot else {
            startAction = nil
            lifecycleAction = nil
            return
        }

        let activeTask = snapshot.activeTask.flatMap { active in
            snapshot.taskRows.first { $0.taskID == active.taskID && $0.state == .active }
        } ?? snapshot.taskRows.first { $0.state == .active }

        if activeTask == nil,
           let recommendedID = snapshot.recommendation.taskID,
           let recommended = snapshot.taskRows.first(where: {
               $0.taskID == recommendedID && $0.state == .ready
           }) {
            startAction = .start(taskID: recommended.taskID, title: recommended.title)
        } else {
            startAction = nil
        }

        if let activeTask {
            lifecycleAction = .pause(taskID: activeTask.taskID, title: activeTask.title)
            return
        }

        let resumable = snapshot.taskRows.filter {
            $0.state == .paused
                && $0.acceptedBreak == nil
                && $0.latestPauseReason != .endingWorkday
        }
        if resumable.count == 1, let pausedTask = resumable.first {
            lifecycleAction = .resume(taskID: pausedTask.taskID, title: pausedTask.title)
        } else {
            lifecycleAction = nil
        }
    }

    var startLabel: String {
        guard case let .start(_, title) = startAction else {
            return "Start Recommended Task"
        }
        return "Start Recommended Task: \(title)"
    }

    var lifecycleLabel: String {
        switch lifecycleAction {
        case let .pause(_, title): "Pause Current Task: \(title)"
        case let .resume(_, title): "Resume Paused Task: \(title)"
        default: "Pause or Resume Current Task"
        }
    }
}

@MainActor
struct TaskKeyboardCommands: Commands {
    @ObservedObject var model: AppModel
    let isAvailable: Bool

    private var state: TaskKeyboardCommandState {
        TaskKeyboardCommandState(
            snapshot: model.todaySnapshot,
            commandIsPending: model.isAnyTaskCommandPending,
            commandsAreAvailable: isAvailable
        )
    }

    var body: some Commands {
        CommandMenu("Task") {
            Button(state.startLabel) {
                perform(state.startAction)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(state.startAction == nil)

            Button(state.lifecycleLabel) {
                perform(state.lifecycleAction)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(state.lifecycleAction == nil)
        }
    }

    private func perform(_ action: TaskKeyboardAction?) {
        guard let action else { return }
        model.applyTaskCommand(action.command, taskID: action.taskID)
    }
}
