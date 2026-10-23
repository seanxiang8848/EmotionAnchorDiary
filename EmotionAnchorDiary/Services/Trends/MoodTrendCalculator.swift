import Foundation

/// 心情趋势的纯计算逻辑。
///
/// 这里刻意不依赖 Core Data、SwiftUI 或当前日期，全部通过参数注入，
/// 这样 7 天 / 30 天的起止边界、同一天多条记录的平均值都能用单元测试锁定。
enum MoodTrendCalculator {
    /// 一条心情记录。
    struct MoodSample {
        let date: Date
        let score: Double
    }

    /// 图表上的一个点：某一天所有记录的平均心情。
    struct MoodPoint: Identifiable, Equatable {
        let day: Date
        let score: Double

        var id: Date { day }
    }

    /// 把记录按天分组，同一天多条记录取平均值，并按日期升序返回。
    ///
    /// - Parameters:
    ///   - samples: 全部心情记录；落在时间窗口之外的会被忽略。
    ///   - rangeDays: 窗口覆盖的天数，**包含今天**（7 或 30）。
    ///   - referenceDate: 计算所用的“今天”，测试可注入固定值。
    ///   - calendar: 用于计算“一天”的边界，测试可注入固定时区。
    static func dailyAveragePoints(
        from samples: [MoodSample],
        rangeDays: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [MoodPoint] {
        guard rangeDays > 0 else { return [] }

        let today = calendar.startOfDay(for: referenceDate)
        guard let firstDay = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: today),
              let endOfWindow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        // 窗口为 [firstDay, endOfWindow)：既含最早的边界日，也含今天的最后一刻。
        let grouped = Dictionary(grouping: samples.compactMap { sample -> (Date, Double)? in
            guard sample.score.isFinite else { return nil }
            guard sample.date >= firstDay, sample.date < endOfWindow else { return nil }
            return (calendar.startOfDay(for: sample.date), sample.score)
        }, by: { $0.0 })

        return grouped
            .map { day, values in
                let average = values.map { $0.1 }.reduce(0, +) / Double(values.count)
                return MoodPoint(day: day, score: average)
            }
            .sorted { $0.day < $1.day }
    }
}
