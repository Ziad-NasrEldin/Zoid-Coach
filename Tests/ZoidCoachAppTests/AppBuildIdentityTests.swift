import Testing
@testable import ZoidCoachApp

@Test
func appBuildIdentityExposesStampedCommitAndState() {
    let commit = String(repeating: "a", count: 40)
    let identity = AppBuildIdentity(
        infoDictionary: [
            "ZoidCoachGitCommit": commit,
            "ZoidCoachGitState": "clean",
            "ZoidCoachBuildIdentity": "zoid-coach-\(commit)-clean"
        ]
    )

    #expect(identity.commit == commit)
    #expect(identity.state == "clean")
    #expect(identity.identity == "zoid-coach-\(commit)-clean")
    #expect(identity.shortLabel == "aaaaaaaa CLEAN")
}

@Test
func unpackagedBuildIdentityIsExplicitlyDevelopmentOnly() {
    let identity = AppBuildIdentity(infoDictionary: [:])

    #expect(identity.shortLabel == "unpackag DEVELOPMENT")
    #expect(identity.identity == "zoid-coach-unpackaged-development")
}
