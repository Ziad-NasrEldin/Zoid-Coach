import CryptoKit
import Foundation
import Security

public protocol EvidenceCiphering: Sendable {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

public struct LocalEvidenceCipher: EvidenceCiphering, Sendable {
    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == 32 else { throw LocalEvidenceCipherError.invalidKey }
        key = SymmetricKey(data: keyData)
    }

    public init(service: String = "com.ziadnasreldin.ZoidCoach.evidence", account: String = "ocr-encryption-key-v1") throws {
        let keyData = try Self.loadOrCreateKey(service: service, account: account)
        try self.init(keyData: keyData)
    }

    public func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw LocalEvidenceCipherError.encrypt }
        return combined
    }

    public func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private static func loadOrCreateKey(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw LocalEvidenceCipherError.keychain(status) }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw LocalEvidenceCipherError.random(randomStatus) }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: bytes
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            var retryResult: CFTypeRef?
            let retryStatus = SecItemCopyMatching(query as CFDictionary, &retryResult)
            guard retryStatus == errSecSuccess, let existing = retryResult as? Data else { throw LocalEvidenceCipherError.keychain(retryStatus) }
            return existing
        }
        guard addStatus == errSecSuccess else { throw LocalEvidenceCipherError.keychain(addStatus) }
        return bytes
    }
}

public enum LocalEvidenceCipherError: LocalizedError {
    case invalidKey
    case encrypt
    case keychain(OSStatus)
    case random(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "The local evidence encryption key has an invalid length."
        case .encrypt: "The local OCR evidence could not be encrypted."
        case let .keychain(status): "Keychain could not provide the local evidence key (\(status))."
        case let .random(status): "A secure local evidence key could not be generated (\(status))."
        }
    }
}
