import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@Test
func calendarScheduleReceiptRequiresTheExactCommittedPerTaskCommandSet() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderDueDate, entityID: "task-1")
    ]
    let committed = required

    #expect(AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: committed))
}

@Test
func sameSizedWrongCalendarScheduleCommandSetIsRejected() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderDueDate, entityID: "task-1")
    ]
    let sameSizedWrong: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-2")
    ]

    #expect(!AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: sameSizedWrong))
}

@Test
func incompleteCalendarScheduleCommandSetIsRejected() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1")
    ]
    let incomplete: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1")
    ]

    #expect(!AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: incomplete))
}

@Test
func ambiguousCalendarReplyRestoresAsReconcilingInsteadOfNothingWritten() throws {
    var state = CalendarPlanApprovalState()
    state.begin(
        entries: [DailyPlanEntry(reminderID: "task-1", rank: 1, isMainObjective: true, estimateMinutes: 30)],
        titlesByReminderID: ["task-1": "Write proposal"],
        availableMinutes: 120,
        fixedCommitmentMinutes: 30,
        usesCalendarAvailability: true
    )
    state.markReconciling(approvedAt: Date(timeIntervalSince1970: 1_752_489_600))
    let receipt = try #require(state.receipt)

    var relaunched = CalendarPlanApprovalState()
    relaunched.restore(receipt)

    #expect(relaunched.writeState == .reconciling)
    #expect(relaunched.receipt?.summary.contains("may already be queued") == true)
    #expect(relaunched.receipt?.summary.contains("Nothing was written") == false)
}
