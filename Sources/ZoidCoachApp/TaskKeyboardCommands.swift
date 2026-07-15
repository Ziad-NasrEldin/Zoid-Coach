import SwiftUI
import ZoidCoachCore

enum TaskKeyboardShortcut: String, CaseIterable {
    case start = "s"
    case pauseOrResume = "p"
    case switchTask = "k"
    case complete = "return"

    var key: KeyEquivalent {
        switch self {
        case .complete: .return
        default: KeyEquivalent(Character(rawValue))
        }
    }

    static let modifiers: EventModifiers = [.command, .option]
}

enum TaskKeyboardAction: Equatable {
    case start(taskID: String, title: String)
    case pause(taskID: String, title: String)
    case resume(taskID: String, title: String)
    case switchTask(taskID: String, title: String, fromTitle: String)
    case complete(taskID: String, title: String)

    var command: TaskActivityCommand {
        switch self {
        case .start: .start
        case .pause: .pauseDoneForNow
        case .resume: .resume
        case .switchTask: .start
        case .complete: .complete
        }
    }

    var taskID: String {
        switch self {
        case let .start(taskID, _),
             let .pause(taskID, _),
             let .resume(taskID, _),
             let .switchTask(taskID, _, _),
             let .complete(taskID, _):
            taskID
        }
    }
}

struct TaskKeyboardCommandState: Equatable {
    let startAction: TaskKeyboardAction?
    let lifecycleAction: TaskKeyboardAction?
    let switchAction: TaskKeyboardAction?
    let completeAction: TaskKeyboardAction?

    init(
        snapshot: TodaySnapshot?,
        commandIsPending: Bool,
        commandsAreAvailable: Bool = true
    ) {
        guard commandsAreAvailable, !commandIsPending, let snapshot else {
            startAction = nil
            lifecycleAction = nil
            switchAction = nil
            completeAction = nil
            return
        }

        let activeTask = snapshot.activeTask.flatMap { active in
            snapshot.taskRows.first { $0.taskID == active.taskID && $0.state == .active }
        } ?? snapshot.taskRows.first { $0.state == .active }

        let recommended = snapshot.recommendation.taskID.flatMap { recommendedID in
            snapshot.taskRows.first {
                $0.taskID == recommendedID && $0.state == .ready
            }
        }

        let switchTarget: TodayTaskRow?
        if let activeTask,
           snapshot.recommendation.taskID == activeTask.taskID {
            let readyAlternatives = snapshot.taskRows.filter {
                $0.taskID != activeTask.taskID && $0.state == .ready
            }
            switchTarget = readyAlternatives.count == 1 ? readyAlternatives[0] : nil
        } else {
            switchTarget = recommended
        }

        if activeTask == nil, let recommended {
            startAction = .start(taskID: recommended.taskID, title: recommended.title)
        } else {
            startAction = nil
        }

        if let activeTask {
            lifecycleAction = .pause(taskID: activeTask.taskID, title: activeTask.title)
            completeAction = .complete(taskID: activeTask.taskID, title: activeTask.title)
            if let switchTarget {
                switchAction = .switchTask(
                    taskID: switchTarget.taskID,
                    title: switchTarget.title,
                    fromTitle: activeTask.title
                )
            } else {
                switchAction = nil
            }
            return
        }

        let resumable = snapshot.taskRows.filter {
            $0.state == .paused
                && $0.acceptedBreak == nil
                && $0.latestPauseReason != .endingWorkday
        }
        if resumable.count == 1, let pausedTask = resumable.first {
            lifecycleAction = .resume(taskID: pausedTask.taskID, title: pausedTask.title)
            completeAction = .complete(taskID: pausedTask.taskID, title: pausedTask.title)
        } else {
            lifecycleAction = nil
            completeAction = nil
        }
        switchAction = nil
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

    var switchLabel: String {
        guard case let .switchTask(_, title, fromTitle) = switchAction else {
            return "Switch to Recommended Task"
        }
        return "Switch from \(fromTitle) to \(title) and Preserve Time"
    }

    var completeLabel: String {
        guard case let .complete(_, title) = completeAction else {
            return "Complete Current Task"
        }
        return "Complete Task: \(title)"
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
            .keyboardShortcut(TaskKeyboardShortcut.start.key, modifiers: TaskKeyboardShortcut.modifiers)
            .disabled(state.startAction == nil)

            Button(state.lifecycleLabel) {
                perform(state.lifecycleAction)
            }
            .keyboardShortcut(TaskKeyboardShortcut.pauseOrResume.key, modifiers: TaskKeyboardShortcut.modifiers)
            .disabled(state.lifecycleAction == nil)

            Divider()

            Button(state.switchLabel) {
                perform(state.switchAction)
            }
            .keyboardShortcut(TaskKeyboardShortcut.switchTask.key, modifiers: TaskKeyboardShortcut.modifiers)
            .disabled(state.switchAction == nil)

            Button(state.completeLabel) {
                perform(state.completeAction)
            }
            .keyboardShortcut(TaskKeyboardShortcut.complete.key, modifiers: TaskKeyboardShortcut.modifiers)
            .disabled(state.completeAction == nil)
        }
    }

    private func perform(_ action: TaskKeyboardAction?) {
        guard let action else { return }
        model.applyTaskCommand(action.command, taskID: action.taskID)
    }
}
