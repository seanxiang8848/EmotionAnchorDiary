import CryptoKit
import Foundation
import Security

/// Handles AES.GCM encryption for diary entries and stores keys securely in Keychain.
final class CryptoManager {
    static let shared: CryptoManager = {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            // UI tests use an in-memory store and a process-local key so they do not
            // depend on Keychain entitlements in unsigned simulator builds.
            return CryptoManager(testKey: SymmetricKey(size: .bits256))
        }
        return CryptoManager()
    }()

    private let keychainKey = "com.emotionanchor.cryptoKey"
    private let keyLength = 32
    private let testKey: SymmetricKey?

    /// Allows unit tests to verify AES-GCM without depending on simulator Keychain entitlements.
    init(testKey: SymmetricKey? = nil) {
        self.testKey = testKey
    }

    /// Encrypts plain text using AES.GCM
    func encrypt(_ plainText: String) throws -> Data {
        let data = Data(plainText.utf8)
        let key: SymmetricKey
        if let testKey {
            key = testKey
        } else {
            key = try loadOrCreateSymmetricKey()
        }
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined ?? Data()
    }

    /// Decrypts AES.GCM data back into human-readable text
    func decrypt(_ cipherData: Data) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: cipherData)
        // A missing key must fail closed; creating a replacement would hide data loss.
        let key: SymmetricKey
        if let testKey {
            key = testKey
        } else {
            key = SymmetricKey(data: try loadKeyData())
        }
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return String(decoding: decrypted, as: UTF8.self)
    }

    func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func loadKeyData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard data.count == keyLength else {
            throw NSError(domain: "CryptoManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid encryption key length"])
        }
        return data
    }

    /// Never encrypt with an in-memory key that cannot survive an app restart.
    private func loadOrCreateSymmetricKey() throws -> SymmetricKey {
        do {
            return SymmetricKey(data: try loadKeyData())
        } catch {
            // Create a key only when Keychain confirms that no key exists.
            let status = (error as NSError).code
            guard status == Int(errSecItemNotFound) else { throw error }
        }

        let generatedKey = SymmetricKey(size: .bits256)
        let keyData = generatedKey.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        return SymmetricKey(data: keyData)
    }

    private func saveKeyData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: keychainKey
            ]
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(match as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
