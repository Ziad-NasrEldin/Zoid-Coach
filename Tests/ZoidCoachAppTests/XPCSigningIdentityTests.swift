import Testing
@testable import ZoidCoachInfrastructure

struct XPCSigningIdentityTests {
    private let allowed = [
        "com.ziadnasreldin.ZoidCoach",
        "com.ziadnasreldin.ZoidCoach.agent",
    ] as Set<String>

    @Test
    func acceptsOnlyTheExplicitAppAndAgentSigningIdentifiers() {
        #expect(SameUserXPCConnectionAuthorizer.allowsSigningIdentity(
            identifier: "com.ziadnasreldin.ZoidCoach",
            allowedIdentifiers: allowed
        ))
        #expect(SameUserXPCConnectionAuthorizer.allowsSigningIdentity(
            identifier: "com.ziadnasreldin.ZoidCoach.agent",
            allowedIdentifiers: allowed
        ))
        #expect(!SameUserXPCConnectionAuthorizer.allowsSigningIdentity(
            identifier: "com.ziadnasreldin.ZoidCoach.attacker",
            allowedIdentifiers: allowed
        ))
    }
}
