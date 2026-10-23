import CoreData
import Foundation

extension Goal {
    /// Presents Core Data's transformable NSArray field as a Swift string array.
    var keywordList: [String] {
        get { keywords as? [String] ?? [] }
        set { keywords = newValue as NSArray }
    }
}

// MARK: - 进度（按天去重 + 时间窗口）

extension Goal {
    /// 时间窗口天数，例如 7 表示「最近 7 天」；至少按 1 天处理。
    var effectivePeriodDays: Int { max(1, Int(periodDays)) }

    /// 周期内需要完成的天数，例如 3 表示「7 天内完成 3 天」；至少按 1 天处理。
    var effectiveTargetDays: Int { max(1, Int(targetFrequency)) }

    /// 最近 ``effectivePeriodDays`` 天内，有多少天至少有一篇日记命中了该目标。
    ///
    /// 同一天写多篇只算一天；超出窗口的记录不再计入。
    func completedDays(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        let dates = (entries as? Set<Entry>)?.compactMap { $0.createdAt } ?? []
        return GoalProgressCalculator.completedDays(
            from: dates,
            periodDays: effectivePeriodDays,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// 0...1 的完成度；达到目标后停在 1，不会因为继续写日记而超过。
    func progress(referenceDate: Date = Date(), calendar: Calendar = .current) -> Double {
        min(1, Double(completedDays(referenceDate: referenceDate, calendar: calendar)) / Double(effectiveTargetDays))
    }

    /// 供进度条使用的当前完成度。
    var progressValue: Double { progress() }

    /// 例如「最近 7 天内完成 3 天」。
    var goalRuleText: String {
        "最近 \(effectivePeriodDays) 天内完成 \(effectiveTargetDays) 天"
    }
}
