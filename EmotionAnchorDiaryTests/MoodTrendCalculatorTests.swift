import XCTest
@testable import EmotionAnchorDiary

/// 覆盖心情趋势的日期边界与同日平均，全部使用固定日历和固定“今天”。
final class MoodTrendCalculatorTests: XCTestCase {

    // GMT + 公历，保证 startOfDay 对 1970-01-01T00:00:00Z 就是自身，断言可读。
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private let referenceDate = Date(timeIntervalSince1970: 0)

    /// 相对“今天”偏移若干天的某个时刻。
    private func date(days: Int, hour: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: referenceDate)!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func points(
        for samples: [MoodTrendCalculator.MoodSample],
        rangeDays: Int
    ) -> [MoodTrendCalculator.MoodPoint] {
        MoodTrendCalculator.dailyAveragePoints(
            from: samples,
            rangeDays: rangeDays,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// 同一天多条记录取平均值（PR-15）。
    func testSameDayRecordsAreAveraged() {
        let result = points(
            for: [
                MoodTrendCalculator.MoodSample(date: date(days: 0, hour: 9), score: 2),
                MoodTrendCalculator.MoodSample(date: date(days: 0, hour: 21), score: 4)
            ],
            rangeDays: 7
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.day, referenceDate)
        XCTAssertEqual(result.first?.score, 3)
    }

    /// 窗口为 [今天-6, 明天)，最早一天和今天都要算进来。
    func testSevenDayWindowIncludesOldestBoundaryDayAndToday() {
        let result = points(
            for: [
                MoodTrendCalculator.MoodSample(date: date(days: -6), score: 1),
                MoodTrendCalculator.MoodSample(date: date(days: 0, hour: 23), score: 5)
            ],
            rangeDays: 7
        )

        XCTAssertEqual(result.map { $0.score }, [1, 5])
    }

    /// 早于窗口起点的记录要被丢掉（PR-15 的 7/30 天范围）。
    func testRecordsOlderThanTheWindowAreIgnored() {
        let result = points(
            for: [MoodTrendCalculator.MoodSample(date: date(days: -7), score: 1)],
            rangeDays: 7
        )

        XCTAssertTrue(result.isEmpty)
    }

    /// 30 天范围要能看到 20 天前的记录。
    func testThirtyDayRangeKeepsOlderRecords() {
        let result = points(
            for: [MoodTrendCalculator.MoodSample(date: date(days: -20), score: 4)],
            rangeDays: 30
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.score, 4)
    }

    /// 未来的记录不应出现在趋势里。
    func testFutureRecordsAreExcluded() {
        let result = points(
            for: [
                MoodTrendCalculator.MoodSample(date: date(days: 0), score: 3),
                MoodTrendCalculator.MoodSample(date: date(days: 1), score: 5)
            ],
            rangeDays: 7
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.score, 3)
    }

    /// 没有记录时返回空，界面据此显示空状态（PR-15）。
    func testEmptySamplesProduceNoPoints() {
        XCTAssertTrue(points(for: [], rangeDays: 7).isEmpty)
        XCTAssertTrue(points(for: [], rangeDays: 30).isEmpty)
    }

    /// 非法的范围天数不应产生任何点，避免除零或负窗口。
    func testNonPositiveRangeProducesNoPoints() {
        let sample = [MoodTrendCalculator.MoodSample(date: date(days: 0), score: 3)]

        XCTAssertTrue(points(for: sample, rangeDays: 0).isEmpty)
        XCTAssertTrue(points(for: sample, rangeDays: -7).isEmpty)
    }

    /// 结果按日期升序，图表才不会左右跳动。
    func testPointsAreSortedByDay() {
        let result = points(
            for: [
                MoodTrendCalculator.MoodSample(date: date(days: 0), score: 4),
                MoodTrendCalculator.MoodSample(date: date(days: -3), score: 2),
                MoodTrendCalculator.MoodSample(date: date(days: -1), score: 3)
            ],
            rangeDays: 7
        )

        XCTAssertEqual(result.map { $0.score }, [2, 3, 4])
    }
}
