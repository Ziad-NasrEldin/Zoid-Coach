import Testing
import ZoidCoachCore
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


    @Test
    func qaClientListenerAndPeerValidationUseOneRuntimeIdentity() throws {
        let runtimeEnvironment = try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", "/tmp/zoid-qa/xpc-agreement"],
            processEnvironment: [:]
        ).environment
        let configuration = TodayDashboardXPCConfiguration(
            runtimeEnvironment: runtimeEnvironment
        )
        let client = TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)

        #expect(configuration.machServiceName == runtimeEnvironment.identity.machServiceName)
        #expect(client.configuredMachServiceName == configuration.machServiceName)
        #expect(configuration.allowedSigningIdentifiers == [
            runtimeEnvironment.identity.appSigningIdentifier,
            runtimeEnvironment.identity.agentSigningIdentifier,
        ])
        #expect(SameUserXPCConnectionAuthorizer.allowsSigningIdentity(
            identifier: runtimeEnvironment.identity.appSigningIdentifier,
            allowedIdentifiers: configuration.allowedSigningIdentifiers
        ))
        #expect(!SameUserXPCConnectionAuthorizer.allowsSigningIdentity(
            identifier: RuntimeIdentity.production.appSigningIdentifier,
            allowedIdentifiers: configuration.allowedSigningIdentifiers
        ))
    }
}
