import Testing
@testable import ZoidCoachApp

@Test
func taskAccessibilityIdentityIsOpaqueStableAndDistinct() {
    let privateID = "arbitrary-private-reminder-id / account@example.com"
    let first = TaskAccessibilityIdentity.opaqueToken(forPersistedID: privateID)
    let second = TaskAccessibilityIdentity.opaqueToken(forPersistedID: privateID)
    let other = TaskAccessibilityIdentity.opaqueToken(forPersistedID: "different-private-reminder-id")

    #expect(first == second)
    #expect(first != other)
    #expect(!first.contains(privateID))
    #expect(!first.contains("account@example.com"))
    #expect(first.count == 32)
    #expect(first.allSatisfy { $0.isHexDigit })
}

@Test
func pauseActionAccessibilityIdentifiersAreStableAndTaskScoped() {
    let taskID = "private-reminder-id"
    let token = TaskAccessibilityIdentity.opaqueToken(forPersistedID: taskID)

    #expect(TaskAccessibilityIdentity.pauseAction(.break, forPersistedID: taskID) == "today.task.\(token).pause.break")
    #expect(TaskAccessibilityIdentity.pauseAction(.externalInterruption, forPersistedID: taskID) == "today.task.\(token).pause.external-interruption")
    #expect(TaskAccessibilityIdentity.pauseAction(.doneForNow, forPersistedID: taskID) == "today.task.\(token).pause.done-for-now")
    #expect(TaskAccessibilityIdentity.pauseAction(.endOfDay, forPersistedID: taskID) == "today.task.\(token).pause.end-of-day")
    #expect(TaskAccessibilityIdentity.pauseAction(.blocked, forPersistedID: taskID) == "today.task.\(token).pause.blocked")
}
