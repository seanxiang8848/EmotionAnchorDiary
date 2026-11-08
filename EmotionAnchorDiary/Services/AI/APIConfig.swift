import Foundation
import Security

/// 支持的 AI 服务商。三者都走 OpenAI 兼容的 `/chat/completions` 协议，
/// 所以同一套请求代码可以直接对接 DeepSeek、OpenAI 以及任何兼容网关。
enum AIProvider: String, CaseIterable, Identifiable {
    case deepseek
    case openai
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .custom: return "自定义（OpenAI 兼容）"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4o-mini"
        case .custom: return ""
        }
    }

    var keyHint: String {
        switch self {
        case .deepseek: return "在 platform.deepseek.com 创建，形如 sk-…"
        case .openai: return "在 platform.openai.com 创建，形如 sk-…"
        case .custom: return "由你的服务商提供"
        }
    }
}

/// AI 服务的连接配置。密钥不放在这里，只保存在 Keychain。
struct APIConfig: Equatable {
    let provider: AIProvider
    let baseURL: URL
    let model: String

    static let providerKey = "aiProvider"
    static let baseURLKey = "aiBaseURL"
    static let modelKey = "aiModel"

    /// 没有保存过配置时使用的默认值（DeepSeek）。
    static let fallback = APIConfig(
        provider: .deepseek,
        baseURL: URL(string: "https://api.deepseek.com/v1")!,
        model: "deepseek-chat"
    )

    var chatCompletionsURL: URL {
        baseURL.appendingPathComponent("chat/completions")
    }

    var displayName: String {
        "\(provider.displayName) · \(model)"
    }

    /// 读取用户保存的配置；从未配置过时返回 nil。
    static func load() -> APIConfig? {
        let defaults = UserDefaults.standard
        guard let rawProvider = defaults.string(forKey: providerKey),
              let provider = AIProvider(rawValue: rawProvider),
              let baseURLString = defaults.string(forKey: baseURLKey),
              let model = defaults.string(forKey: modelKey) else {
            return nil
        }
        return validated(provider: provider, baseURLString: baseURLString, model: model)
    }

    /// 读取配置，未配置时退回默认值，供设置页展示。
    static func current() -> APIConfig {
        load() ?? fallback
    }

    /// 只接受 HTTPS 地址和合法模型名，避免把密钥发到明文地址。
    static func validated(provider: AIProvider, baseURLString: String, model: String) -> APIConfig? {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              !trimmedModel.isEmpty else {
            return nil
        }
        return APIConfig(provider: provider, baseURL: url, model: trimmedModel)
    }

    static func save(_ config: APIConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.provider.rawValue, forKey: providerKey)
        defaults.set(config.baseURL.absoluteString, forKey: baseURLKey)
        defaults.set(config.model, forKey: modelKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: baseURLKey)
        defaults.removeObject(forKey: modelKey)
        // 旧版本把自定义后端地址存在这个 key 里，一并清掉。
        defaults.removeObject(forKey: "aiServiceEndpoint")
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

    /// 是否已经配置了可用的密钥（不读取明文内容到调用方）。
    static var isConfigured: Bool {
        guard let key = load() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
