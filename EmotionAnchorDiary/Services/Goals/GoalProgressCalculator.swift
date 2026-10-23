import Foundation

/// 目标进度的纯计算逻辑：把「命中该目标的日记时间」折算成「周期内的完成天数」。
///
/// 产品口径（按天去重 + 时间窗口）：
/// - 同一天写多篇日记只算**一天**；
/// - 超出时间窗口的记录**不再计入**，因此进度会随时间自然回落；
/// - 未来的记录不计入。
///
/// 这里不依赖 Core Data 和当前日期，方便单测锁定边界。
enum GoalProgressCalculator {
    /// - Parameters:
    ///   - dates: 命中该目标的日记时间。
    ///   - periodDays: 时间窗口天数，**包含今天**（7 表示「最近 7 天」）。
    ///   - referenceDate: 计算所用的“今天”，测试可注入。
    ///   - calendar: 用于计算“一天”的边界，测试可注入。
    static func completedDays(
        from dates: [Date],
        periodDays: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard periodDays > 0 else { return 0 }

        let today = calendar.startOfDay(for: referenceDate)
        guard let firstDay = calendar.date(byAdding: .day, value: -(periodDays - 1), to: today),
              let endOfWindow = calendar.date(byAdding: .day, value: 1, to: today) else { return 0 }

        var days = Set<Date>()
        for date in dates where date >= firstDay && date < endOfWindow {
            days.insert(calendar.startOfDay(for: date))
        }
        return days.count
    }
}
