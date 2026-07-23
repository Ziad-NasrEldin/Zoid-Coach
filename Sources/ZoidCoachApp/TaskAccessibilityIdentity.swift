import CryptoKit
import Foundation

enum TaskAccessibilityIdentity {
    enum PauseAction: String {
        case `break`
        case externalInterruption = "external-interruption"
        case doneForNow = "done-for-now"
        case endOfDay = "end-of-day"
        case blocked
    }

    static func opaqueToken(forPersistedID persistedID: String) -> String {
        let input = Data("zoid-coach.accessibility.task.v1\u{0}\(persistedID)".utf8)
        return SHA256.hash(data: input)
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func pauseAction(_ action: PauseAction, forPersistedID persistedID: String) -> String {
        "today.task.\(opaqueToken(forPersistedID: persistedID)).pause.\(action.rawValue)"
    }
}
