import Foundation

/// Interfaces with the AI service to transform diary summaries into empathy responses.
struct EmpathyCard: Codable {
    let mood: String
    let empathy: String
    let suggestions: [String]
}

final class EmotionCoachService {
    private static let fallbackCards: [EmpathyCard] = [
        EmpathyCard(
            mood: "放松",
            empathy: "我在，先给自己一个拥抱。无论发生什么，你已经尽力了。",
            suggestions: ["做三次深呼吸", "写下一个让你感激的小事"]
        ),
        EmpathyCard(
            mood: "稳住",
            empathy: "情绪像浪潮，会来会去。你可以慢慢整理，让它安全地流动。",
            suggestions: ["喝一杯温水", "给自己 5 分钟什么都不做"]
        ),
        EmpathyCard(
            mood: "被倾听",
            empathy: "谢谢你信任自己写下这一切。你值得被理解，也值得被善待。",
            suggestions: ["记录此刻的身体感受", "联系一个让你安心的人"]
        )
    ]

    static func fallbackCard() -> EmpathyCard {
        fallbackCards.randomElement() ?? EmpathyCard(
            mood: "陪伴",
            empathy: "此刻你不是一个人，我在这里听你说。",
            suggestions: ["闭眼听一首喜欢的歌", "对自己说一句温柔的话"]
        )
    }

    private let endpointProvider: () -> URL?
    private let apiKeyProvider: () -> String?

    init(endpointProvider: @escaping () -> URL?, apiKeyProvider: @escaping () -> String?) {
        self.endpointProvider = endpointProvider
        self.apiKeyProvider = apiKeyProvider
    }

    /// Sends a short summary to the server and returns an EmpathyCard.
    func fetchEmpathyCard(summary: String) async throws -> EmpathyCard {
        guard let endpoint = endpointProvider(), endpoint.scheme == "https" else {
            throw NSError(domain: "EmotionCoach", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing HTTPS endpoint"])
        }
        guard let apiKey = apiKeyProvider() else {
            throw NSError(domain: "EmotionCoach", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["summary": summary])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(domain: "EmotionCoach", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI service unavailable"])
        }

        return try JSONDecoder().decode(EmpathyCard.self, from: data)
    }

    func fallbackCard() -> EmpathyCard {
        Self.fallbackCard()
    }
}

/// Creates a compact extractive summary locally before any optional cloud request.
enum LocalDiarySummarizer {
    static func summarize(_ text: String, maximumCharacters: Int = 300) -> String {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let extracted = sentences.prefix(3).joined(separator: "。")
        guard extracted.count > maximumCharacters else { return extracted }
        let end = extracted.index(extracted.startIndex, offsetBy: maximumCharacters)
        return String(extracted[..<end])
    }
}
