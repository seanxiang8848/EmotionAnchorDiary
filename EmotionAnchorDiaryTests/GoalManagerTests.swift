import CoreData
import XCTest
@testable import EmotionAnchorDiary

@MainActor
final class GoalManagerTests: XCTestCase {

    private var context: NSManagedObjectContext!
    private var manager: GoalManager!

    // GMT + 公历，保证 startOfDay 对 1970-01-01T00:00:00Z 就是自身，断言可读。
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

    /// 造一篇命中「散步」的日记并关联到目标。
    @discardableResult
    private func makeWalkEntry(days: Int, hour: Int = 10) throws -> Entry {
        let entry = try CoreDataTestSupport.makeEntry(
            in: context,
            text: "去散步了",
            createdAt: date(days: days, hour: hour)
        )
        _ = try manager.associateGoals(with: entry, plainText: "去散步了")
        return entry
    }

    private func completedDays(of goal: Goal) -> Int {
        goal.completedDays(referenceDate: referenceDate, calendar: calendar)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        context = try CoreDataTestSupport.makeInMemoryContext()
        manager = GoalManager(context: context)
    }

    override func tearDownWithError() throws {
        manager = nil
        context = nil
        try super.tearDownWithError()
    }

    // MARK: - 创建

    func testCreateGoalTrimsTitleAndNormalizesKeywords() throws {
        let goal = try manager.createGoal(
            title: "  每天散步  ",
            keywords: [" 散步 ", "散步", "   ", "慢跑"],
            targetFrequency: 5,
            periodDays: 7
        )

        XCTAssertEqual(goal.title, "每天散步")
        XCTAssertEqual(Set(goal.keywordList), ["散步", "慢跑"])
        XCTAssertEqual(goal.keywordList.count, 2, "关键词应去重")
        XCTAssertEqual(goal.targetFrequency, 5)
        XCTAssertEqual(goal.periodDays, 7)
        XCTAssertEqual(completedDays(of: goal), 0)
        XCTAssertNotNil(goal.id)
        XCTAssertNotNil(goal.lastUpdatedAt)
    }

    func testCreateGoalDefaultsToSevenDayPeriod() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)

        XCTAssertEqual(goal.periodDays, 7)
        XCTAssertEqual(goal.goalRuleText, "最近 7 天内完成 3 天")
    }

    func testCreateGoalRejectsEmptyTitle() {
        XCTAssertThrowsError(
            try manager.createGoal(title: "   ", keywords: ["跑步"], targetFrequency: 3, periodDays: 7)
        )
    }

    func testCreateGoalRejectsInvalidPeriodOrTargetDays() {
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: 3, periodDays: 0)
        )
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: 0, periodDays: 7)
        )
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: -1, periodDays: 7)
        )
    }

    /// 目标天数不能超过周期天数，否则「7 天内完成 9 天」这种规则不可能达成。
    func testCreateGoalRejectsTargetDaysBeyondPeriod() {
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: 9, periodDays: 7)
        )
    }

    func testCreatedGoalsCanBeFetchedBack() throws {
        _ = try manager.createGoal(title: "写日记", keywords: ["日记"], targetFrequency: 5, periodDays: 7)
        _ = try manager.createGoal(title: "早睡", keywords: ["睡觉"], targetFrequency: 3, periodDays: 7)

        XCTAssertEqual(try manager.fetchGoals().count, 2)
    }

    // MARK: - 修改

    func testUpdateGoalReplacesTitleKeywordsPeriodAndTargetDays() throws {
        let goal = try manager.createGoal(title: "旧目标", keywords: ["旧词"], targetFrequency: 2, periodDays: 7)

        try manager.updateGoal(goal, title: " 新目标 ", keywords: ["新词"], targetFrequency: 5, periodDays: 14)

        XCTAssertEqual(goal.title, "新目标")
        XCTAssertEqual(goal.keywordList, ["新词"])
        XCTAssertEqual(goal.targetFrequency, 5)
        XCTAssertEqual(goal.periodDays, 14)
        XCTAssertEqual(goal.goalRuleText, "最近 14 天内完成 5 天")
    }

    func testUpdateGoalRejectsInvalidInput() throws {
        let goal = try manager.createGoal(title: "有效目标", keywords: ["词"], targetFrequency: 2, periodDays: 7)

        XCTAssertThrowsError(
            try manager.updateGoal(goal, title: "", keywords: ["词"], targetFrequency: 3, periodDays: 7)
        )
        XCTAssertThrowsError(
            try manager.updateGoal(goal, title: "有效目标", keywords: ["词"], targetFrequency: 0, periodDays: 7)
        )
        XCTAssertThrowsError(
            try manager.updateGoal(goal, title: "有效目标", keywords: ["词"], targetFrequency: 8, periodDays: 7)
        )
        // 校验失败不应把已保存的目标改坏
        XCTAssertEqual(goal.title, "有效目标")
        XCTAssertEqual(goal.targetFrequency, 2)
        XCTAssertEqual(goal.periodDays, 7)
    }

    // MARK: - 删除

    func testDeleteGoalRemovesItFromTheStore() throws {
        let goal = try manager.createGoal(title: "临时目标", keywords: ["临时"], targetFrequency: 1, periodDays: 7)

        try manager.deleteGoal(goal)

        XCTAssertEqual(try manager.fetchGoals().count, 0)
    }

    func testDeletingGoalDetachesItFromLinkedEntries() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        let entry = try makeWalkEntry(days: 0)
        XCTAssertEqual(entry.goals?.count ?? 0, 1)

        try manager.deleteGoal(goal)

        // 模型的删除规则是 Nullify：目标消失后日记仍在，但不再挂在该目标下
        XCTAssertEqual(try manager.fetchGoals().count, 0)
        XCTAssertEqual(entry.goals?.count ?? 0, 0)
        XCTAssertEqual(try context.fetch(Entry.fetchRequest()).count, 1, "删除目标不应连带删除日记")
    }

    // MARK: - 关键词关联

    func testAssociateGoalsLinksTheEntry() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        // 必须落在基准日的窗口内，否则 completedDays 会当成超期记录
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了", createdAt: date(days: 0))

        let matched = try manager.associateGoals(with: entry, plainText: "今天去散步了")

        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.title, "每天散步")
        XCTAssertEqual(entry.goals?.count ?? 0, 1)
        XCTAssertEqual(completedDays(of: goal), 1)
    }

    func testAssociateGoalsOnlyMatchesGoalsWhoseKeywordsAppear() throws {
        _ = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        _ = try manager.createGoal(title: "每天冥想", keywords: ["冥想"], targetFrequency: 3, periodDays: 7)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天只去散步了")

        let matched = try manager.associateGoals(with: entry, plainText: "今天只去散步了")

        // fetchRequest 没有排序描述符，比对时不去依赖返回顺序
        XCTAssertEqual(Set(matched.compactMap { $0.title }), ["每天散步"])
    }

    func testAssociateGoalsMatchesCaseInsensitively() throws {
        _ = try manager.createGoal(title: "跑步", keywords: ["Run"], targetFrequency: 1, periodDays: 7)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "went for a run")

        let matched = try manager.associateGoals(with: entry, plainText: "went for a RUN")

        XCTAssertEqual(matched.count, 1)
    }

    func testAssociateGoalsLeavesGoalsUntouchedWhenNothingMatches() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天什么都没做", createdAt: date(days: 0))

        let matched = try manager.associateGoals(with: entry, plainText: "今天什么都没做")

        XCTAssertTrue(matched.isEmpty)
        XCTAssertEqual(entry.goals?.count ?? 0, 0)
        XCTAssertEqual(completedDays(of: goal), 0)
    }

    /// 同一篇日记重复关联只挂接一次。
    func testAssociatingTheSameEntryTwiceIsIdempotent() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了", createdAt: date(days: 0))

        let first = try manager.associateGoals(with: entry, plainText: "今天去散步了")
        let second = try manager.associateGoals(with: entry, plainText: "今天去散步了")

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1, "重复关联仍应认为命中了该目标")
        XCTAssertEqual(entry.goals?.count ?? 0, 1)
        XCTAssertEqual(completedDays(of: goal), 1)
    }

    /// 注意：当前实现不会主动解除已建立的挂接。日记改写后不再命中关键词时，
    /// 已经计入的那一天仍然保留。若要「改写即回退」，需要另行解除挂接。
    func testCurrentBehavior_EditingAwayTheKeywordKeepsTheLinkedDay() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了", createdAt: date(days: 0))

        _ = try manager.associateGoals(with: entry, plainText: "今天去散步了")
        let afterRewrite = try manager.associateGoals(with: entry, plainText: "今天什么都没做")

        XCTAssertTrue(afterRewrite.isEmpty)
        XCTAssertEqual(completedDays(of: goal), 1, "已挂接的那一天不会自动回退")
    }

    // MARK: - 按天去重 + 时间窗口

    /// 同一天写多篇只算一天。
    func testTwoEntriesOnTheSameDayCountAsOneDay() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)

        try makeWalkEntry(days: 0, hour: 8)
        try makeWalkEntry(days: 0, hour: 20)

        XCTAssertEqual(completedDays(of: goal), 1)
    }

    /// 不同天各算一天。
    func testEntriesOnThreeDifferentDaysCountAsThreeDays() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)

        try makeWalkEntry(days: -2)
        try makeWalkEntry(days: -1)
        try makeWalkEntry(days: 0)

        XCTAssertEqual(completedDays(of: goal), 3)
        XCTAssertEqual(goal.progress(referenceDate: referenceDate, calendar: calendar), 1)
    }

    /// 超出周期的记录不再计入。
    func testEntriesOutsideThePeriodStopCounting() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)

        try makeWalkEntry(days: -2)
        try makeWalkEntry(days: -10)

        XCTAssertEqual(completedDays(of: goal), 1)
    }

    /// 进度封顶在 1，不会因为继续写日记而超过 100%。
    func testProgressCapsAtOne() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 1, periodDays: 7)

        try makeWalkEntry(days: -2)
        try makeWalkEntry(days: -1)
        try makeWalkEntry(days: 0)

        XCTAssertEqual(completedDays(of: goal), 3)
        XCTAssertEqual(goal.progress(referenceDate: referenceDate, calendar: calendar), 1)
    }

    /// 删掉日记后进度会回落，这是「不存累计计数」带来的好处。
    func testDeletingAnEntryDropsTheProgress() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)
        let entry = try makeWalkEntry(days: 0)
        XCTAssertEqual(completedDays(of: goal), 1)

        context.delete(entry)
        try context.save()

        XCTAssertEqual(completedDays(of: goal), 0)
    }

    /// 周期边界：第 7 天仍算，第 8 天不算。
    func testPeriodBoundaryDays() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3, periodDays: 7)

        try makeWalkEntry(days: -6)
        try makeWalkEntry(days: -7)

        XCTAssertEqual(completedDays(of: goal), 1)
    }
}
