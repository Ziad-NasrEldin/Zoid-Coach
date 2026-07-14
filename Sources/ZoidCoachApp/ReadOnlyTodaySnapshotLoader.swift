import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct ReadOnlyTodaySnapshotLoader: Sendable {
    private let store: TodaySnapshotStore?

    init(runtimeEnvironment: RuntimeEnvironment) {
        store = try? TodaySnapshotStore(
            databaseURL: runtimeEnvironment.databaseURL,
            readOnly: true
        )
    }

    func load() -> TodaySnapshot? {
        try? store?.load()
    }
}
