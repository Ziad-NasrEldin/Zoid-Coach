import Foundation

struct AppBuildIdentity: Equatable, Sendable {
    let commit: String
    let state: String
    let identity: String

    static var current: Self {
        Self(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        let suppliedCommit = infoDictionary["ZoidCoachGitCommit"] as? String
        let suppliedState = infoDictionary["ZoidCoachGitState"] as? String
        let suppliedIdentity = infoDictionary["ZoidCoachBuildIdentity"] as? String
        if suppliedCommit == nil, suppliedState == nil, suppliedIdentity == nil {
            commit = "unpackaged"
            state = "development"
            identity = "zoid-coach-unpackaged-development"
        } else if let suppliedCommit,
                  suppliedCommit.count == 40,
                  suppliedCommit.allSatisfy({
                      ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))
                  }),
                  let suppliedState,
                  ["clean", "dirty"].contains(suppliedState),
                  suppliedIdentity == "zoid-coach-\(suppliedCommit)-\(suppliedState)" {
            commit = suppliedCommit
            state = suppliedState
            identity = suppliedIdentity ?? "zoid-coach-invalid"
        } else {
            commit = "invalid"
            state = "invalid"
            identity = "zoid-coach-invalid"
        }
    }

    var shortLabel: String {
        guard state != "invalid" else { return "INVALID BUILD" }
        return "\(commit.prefix(8)) \(state.uppercased())"
    }
}
