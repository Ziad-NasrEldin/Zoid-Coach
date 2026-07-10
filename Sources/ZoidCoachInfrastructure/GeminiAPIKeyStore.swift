import Foundation
import Security

public protocol GeminiAPIKeyProviding: Sendable {
    func loadAPIKey() throws -> String?
}

public final class GeminiAPIKeyStore: GeminiAPIKeyProviding, @unchecked Sendable {
    public static let service = "com.ziadnasreldin.ZoidCoach.GeminiLive"
    public static let account = "api-key"

    public init() {}

    public func saveAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            try deleteAPIKey()
            return
        }
        let data = Data(key.utf8)
        let query = baseQuery
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw GeminiAPIKeyStoreError.status(updateStatus) }
        var addition = query
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw GeminiAPIKeyStoreError.status(addStatus) }
    }

    public func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw GeminiAPIKeyStoreError.status(status)
        }
        return key
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiAPIKeyStoreError.status(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}

public enum GeminiAPIKeyStoreError: LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Could not access the Gemini API key in Keychain: \(message)"
        }
    }
}
