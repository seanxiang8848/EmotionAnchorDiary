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
}
