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

@Test(arguments: [
    [
        "ZoidCoachGitCommit": "abc",
        "ZoidCoachGitState": "clean",
        "ZoidCoachBuildIdentity": "zoid-coach-abc-clean"
    ],
    [
        "ZoidCoachGitCommit": String(repeating: "A", count: 40),
        "ZoidCoachGitState": "clean",
        "ZoidCoachBuildIdentity": "zoid-coach-\(String(repeating: "A", count: 40))-clean"
    ],
    [
        "ZoidCoachGitCommit": String(repeating: "b", count: 40),
        "ZoidCoachGitState": "maybe",
        "ZoidCoachBuildIdentity": "zoid-coach-\(String(repeating: "b", count: 40))-maybe"
    ],
    [
        "ZoidCoachGitCommit": String(repeating: "c", count: 40),
        "ZoidCoachGitState": "clean",
        "ZoidCoachBuildIdentity": "zoid-coach-\(String(repeating: "d", count: 40))-clean"
    ],
    ["ZoidCoachGitCommit": String(repeating: "e", count: 40)]
])
func malformedOrPartialBuildIdentityFailsClosed(infoDictionary: [String: String]) {
    let identity = AppBuildIdentity(infoDictionary: infoDictionary.mapValues { $0 as Any })

    #expect(identity.commit == "invalid")
    #expect(identity.state == "invalid")
    #expect(identity.identity == "zoid-coach-invalid")
    #expect(identity.shortLabel == "INVALID BUILD")
}
