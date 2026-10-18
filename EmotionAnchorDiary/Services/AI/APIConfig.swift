import Foundation
import Security

/// Loads only the service endpoint. API keys must be entered by the user and stored in Keychain.
struct APIConfig {
    let endpoint: URL
    static let endpointDefaultsKey = "aiServiceEndpoint"

    static func load() -> APIConfig? {
        if let savedEndpoint = UserDefaults.standard.string(forKey: endpointDefaultsKey),
           let config = validated(savedEndpoint) {
            return config
        }

        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let endpointString = dict["AIEndpoint"] else { return nil }
        return validated(endpointString)
    }

    static func validated(_ endpointString: String) -> APIConfig? {
        guard let endpoint = URL(string: endpointString.trimmingCharacters(in: .whitespacesAndNewlines)),
              endpoint.scheme == "https",
              endpoint.host != nil else { return nil }
        return APIConfig(endpoint: endpoint)
    }
}

/// Stores a user-provided AI credential on this device instead of in the app bundle.
enum AIKeyStore {
    private static let service = "com.emotionanchor.diary.ai"
    private static let account = "apiKey"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ apiKey: String) throws {
        let data = Data(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = match
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(insertStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
