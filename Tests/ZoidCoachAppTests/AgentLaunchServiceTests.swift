import Foundation
import Testing
@testable import ZoidCoachApp

struct AgentLaunchServiceTests {
    @Test
    func developmentPackageCannotTakeOwnershipFromTheInstalledApp() {
        #expect(AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/repo/.build/app/Zoid Coach.app")
        ))
        #expect(!AgentLaunchService.isDevelopmentBundle(
            URL(fileURLWithPath: "/Users/example/Applications/Zoid Coach.app")
        ))
    }

    @Test
    func registrationFingerprintChangesWhenTheInstalledAppMoves() {
        let buildCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/tmp/build/Zoid Coach.app")
        )
        let installedCopy = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid Coach.app")
        )

        #expect(buildCopy != installedCopy)
    }

    @Test
    func registrationFingerprintIsStableForTheSameBuildAndPath() {
        let first = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/../Applications/Zoid Coach.app")
        )
        let second = AgentLaunchService.registrationFingerprint(
            build: "8",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Zoid Coach.app")
        )

        #expect(first == second)
    }
}
