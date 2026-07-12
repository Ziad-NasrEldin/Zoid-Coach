import Foundation

struct AppBuildIdentity: Equatable, Sendable {
    let commit: String
    let state: String
    let identity: String

    static var current: Self {
        Self(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        commit = infoDictionary["ZoidCoachGitCommit"] as? String ?? "unpackaged"
        state = infoDictionary["ZoidCoachGitState"] as? String ?? "development"
        identity = infoDictionary["ZoidCoachBuildIdentity"] as? String
            ?? "zoid-coach-unpackaged-development"
    }

    var shortLabel: String {
        "\(commit.prefix(8)) \(state.uppercased())"
    }
}
