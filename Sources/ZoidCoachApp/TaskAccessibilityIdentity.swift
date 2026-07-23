import CryptoKit
import Foundation

enum TaskAccessibilityIdentity {
    static func opaqueToken(forPersistedID persistedID: String) -> String {
        let input = Data("zoid-coach.accessibility.task.v1\u{0}\(persistedID)".utf8)
        return SHA256.hash(data: input)
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
