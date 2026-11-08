/// A small, explicit mood scale used to build a trend from user-selected labels.
struct MoodOption: Identifiable {
    let tag: String
    let score: Double
    var id: String { tag }

    static let all: [MoodOption] = [
        MoodOption(tag: "低落", score: 1),
        MoodOption(tag: "焦虑", score: 2),
        MoodOption(tag: "平静", score: 3),
        MoodOption(tag: "开心", score: 4),
        MoodOption(tag: "有能量", score: 5)
    ]

    static func option(for tag: String) -> MoodOption? {
        all.first { $0.tag == tag }
    }

    static func score(for tag: String) -> Double {
        option(for: tag)?.score ?? 3
    }
}

extension Entry {
    /// 解析后的 AI 分析结果；没分析过或本地数据损坏时返回 nil。
    ///
    /// 结果以 JSON 存在 `aiAnalysisJSON` 里，模型只加字段不改字段，
    /// 旧版本日记读不到分析也不影响正常使用。
    var aiAnalysis: DiaryAnalysis? {
        guard let json = aiAnalysisJSON, !json.isEmpty else { return nil }
        return try? DiaryAnalysisParser.parse(json)
    }

    var aiSuggestions: [String] {
        aiAnalysis?.suggestions ?? []
    }
}
