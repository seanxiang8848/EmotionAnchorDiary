import CoreData
import XCTest
@testable import EmotionAnchorDiary

@MainActor
final class GoalManagerTests: XCTestCase {

    private var context: NSManagedObjectContext!
    private var manager: GoalManager!

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
            targetFrequency: 5
        )

        XCTAssertEqual(goal.title, "每天散步")
        XCTAssertEqual(Set(goal.keywordList), ["散步", "慢跑"])
        XCTAssertEqual(goal.keywordList.count, 2, "关键词应去重")
        XCTAssertEqual(goal.targetFrequency, 5)
        XCTAssertEqual(goal.hits, 0)
        XCTAssertNotNil(goal.id)
        XCTAssertNotNil(goal.lastUpdatedAt)
    }

    func testCreateGoalRejectsEmptyTitle() {
        XCTAssertThrowsError(
            try manager.createGoal(title: "   ", keywords: ["跑步"], targetFrequency: 3)
        )
    }

    func testCreateGoalRejectsInvalidFrequency() {
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: 0)
        )
        XCTAssertThrowsError(
            try manager.createGoal(title: "每天跑步", keywords: ["跑步"], targetFrequency: -1)
        )
    }

    func testCreatedGoalsCanBeFetchedBack() throws {
        _ = try manager.createGoal(title: "写日记", keywords: ["日记"], targetFrequency: 7)
        _ = try manager.createGoal(title: "早睡", keywords: ["睡觉"], targetFrequency: 7)

        XCTAssertEqual(try manager.fetchGoals().count, 2)
    }

    // MARK: - 修改

    func testUpdateGoalReplacesTitleKeywordsAndFrequency() throws {
        let goal = try manager.createGoal(title: "旧目标", keywords: ["旧词"], targetFrequency: 2)

        try manager.updateGoal(goal, title: " 新目标 ", keywords: ["新词"], targetFrequency: 9)

        XCTAssertEqual(goal.title, "新目标")
        XCTAssertEqual(goal.keywordList, ["新词"])
        XCTAssertEqual(goal.targetFrequency, 9)
    }

    func testUpdateGoalRejectsInvalidInput() throws {
        let goal = try manager.createGoal(title: "有效目标", keywords: ["词"], targetFrequency: 2)

        XCTAssertThrowsError(
            try manager.updateGoal(goal, title: "", keywords: ["词"], targetFrequency: 3)
        )
        XCTAssertThrowsError(
            try manager.updateGoal(goal, title: "有效目标", keywords: ["词"], targetFrequency: 0)
        )
        // 校验失败不应把已保存的目标改坏
        XCTAssertEqual(goal.title, "有效目标")
        XCTAssertEqual(goal.targetFrequency, 2)
    }

    // MARK: - 删除

    func testDeleteGoalRemovesItFromTheStore() throws {
        let goal = try manager.createGoal(title: "临时目标", keywords: ["临时"], targetFrequency: 1)

        try manager.deleteGoal(goal)

        XCTAssertEqual(try manager.fetchGoals().count, 0)
    }

    func testDeletingGoalDetachesItFromLinkedEntries() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了")

        _ = try manager.associateGoals(with: entry, plainText: "今天去散步了")
        XCTAssertEqual(entry.goals?.count ?? 0, 1)

        try manager.deleteGoal(goal)

        // 模型的删除规则是 Nullify：目标消失后日记仍在，但不再挂在该目标下
        XCTAssertEqual(try manager.fetchGoals().count, 0)
        XCTAssertEqual(entry.goals?.count ?? 0, 0)
        XCTAssertEqual(try context.fetch(Entry.fetchRequest()).count, 1, "删除目标不应连带删除日记")
    }

    // MARK: - 关键词关联

    func testAssociateGoalsIncrementsHitsAndLinksTheEntry() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了")

        let matched = try manager.associateGoals(with: entry, plainText: "今天去散步了")

        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.title, "每天散步")
        XCTAssertEqual(goal.hits, 1)
        XCTAssertEqual(entry.goals?.count ?? 0, 1)
    }

    func testAssociateGoalsOnlyMatchesGoalsWhoseKeywordsAppear() throws {
        _ = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        _ = try manager.createGoal(title: "每天冥想", keywords: ["冥想"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天只去散步了")

        let matched = try manager.associateGoals(with: entry, plainText: "今天只去散步了")

        XCTAssertEqual(matched.map { $0.title }, ["每天散步"])
    }

    func testAssociateGoalsMatchesCaseInsensitively() throws {
        _ = try manager.createGoal(title: "跑步", keywords: ["Run"], targetFrequency: 1)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "went for a run")

        let matched = try manager.associateGoals(with: entry, plainText: "went for a RUN")

        XCTAssertEqual(matched.count, 1)
    }

    func testAssociateGoalsLeavesGoalsUntouchedWhenNothingMatches() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天什么都没做")

        let matched = try manager.associateGoals(with: entry, plainText: "今天什么都没做")

        XCTAssertTrue(matched.isEmpty)
        XCTAssertEqual(goal.hits, 0)
        XCTAssertEqual(entry.goals?.count ?? 0, 0)
    }

    /// 产品规则：同一篇日记对同一个目标只计一次，重复关联不重复加 hits。
    func testAssociatingTheSameEntryTwiceDoesNotDoubleCount() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了")

        let firstMatch = try manager.associateGoals(with: entry, plainText: "今天去散步了")
        let secondMatch = try manager.associateGoals(with: entry, plainText: "今天去散步了")

        XCTAssertEqual(goal.hits, 1)
        XCTAssertEqual(firstMatch.count, 1)
        XCTAssertEqual(secondMatch.count, 1, "重复关联仍应认为该日记命中了这个目标")
        XCTAssertEqual(entry.goals?.count ?? 0, 1)
    }

    /// 两篇不同的日记命中同一个目标，应各计一次。
    func testTwoDifferentEntriesEachCountOnce() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let morningEntry = try CoreDataTestSupport.makeEntry(in: context, text: "早上散步")
        let eveningEntry = try CoreDataTestSupport.makeEntry(in: context, text: "晚上散步")

        _ = try manager.associateGoals(with: morningEntry, plainText: "早上散步")
        _ = try manager.associateGoals(with: eveningEntry, plainText: "晚上散步")

        XCTAssertEqual(goal.hits, 2)
        XCTAssertEqual(goal.entries?.count ?? 0, 2)
    }

    /// 日记改写后不再命中关键词时，已经记下的次数不会被扣回。
    func testLosingTheKeywordDoesNotDecrementExistingHits() throws {
        let goal = try manager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)
        let entry = try CoreDataTestSupport.makeEntry(in: context, text: "今天去散步了")

        _ = try manager.associateGoals(with: entry, plainText: "今天去散步了")
        let afterRewrite = try manager.associateGoals(with: entry, plainText: "今天什么都没做")

        XCTAssertTrue(afterRewrite.isEmpty)
        XCTAssertEqual(goal.hits, 1, "已计入的进度不回退")
    }
}
