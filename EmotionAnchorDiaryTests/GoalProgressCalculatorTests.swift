import XCTest
@testable import EmotionAnchorDiary

/// 覆盖目标进度的「按天去重 + 时间窗口」规则，全部使用固定日历和固定“今天”。
final class GoalProgressCalculatorTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private let referenceDate = Date(timeIntervalSince1970: 0)

    private func date(days: Int, hour: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: referenceDate)!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func completedDays(_ dates: [Date], periodDays: Int) -> Int {
        GoalProgressCalculator.completedDays(
            from: dates,
            periodDays: periodDays,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// 同一天写多篇只算一天。
    func testSameDayEntriesCountAsOneDay() {
        let result = completedDays([date(days: 0, hour: 8), date(days: 0, hour: 20)], periodDays: 7)

        XCTAssertEqual(result, 1)
    }

    /// 不同天各算一天。
    func testDifferentDaysEachCountOnce() {
        let result = completedDays([date(days: -2), date(days: -1), date(days: 0)], periodDays: 7)

        XCTAssertEqual(result, 3)
    }

    /// 窗口为 [今天-6, 明天)：最早一天和今天都要算进来。
    func testWindowIncludesOldestBoundaryDayAndToday() {
        let result = completedDays([date(days: -6), date(days: 0, hour: 23)], periodDays: 7)

        XCTAssertEqual(result, 2)
    }

    /// 早于窗口的记录不再计入，进度会随时间回落。
    func testEntriesOlderThanTheWindowAreIgnored() {
        XCTAssertEqual(completedDays([date(days: -7)], periodDays: 7), 0)
        XCTAssertEqual(completedDays([date(days: -20)], periodDays: 7), 0)
    }

    /// 更长的周期要能看到更早的记录。
    func testLongerPeriodKeepsOlderEntries() {
        XCTAssertEqual(completedDays([date(days: -20)], periodDays: 30), 1)
    }

    /// 未来的记录不应计入。
    func testFutureEntriesAreIgnored() {
        XCTAssertEqual(completedDays([date(days: 0), date(days: 1)], periodDays: 7), 1)
    }

    /// 没有命中记录时为 0。
    func testNoEntriesProducesZero() {
        XCTAssertEqual(completedDays([], periodDays: 7), 0)
    }

    /// 周期天数非法时不应产生进度，避免算出负窗口。
    func testNonPositivePeriodProducesZero() {
        XCTAssertEqual(completedDays([date(days: 0)], periodDays: 0), 0)
        XCTAssertEqual(completedDays([date(days: 0)], periodDays: -7), 0)
    }
}
