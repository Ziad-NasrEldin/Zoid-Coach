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
