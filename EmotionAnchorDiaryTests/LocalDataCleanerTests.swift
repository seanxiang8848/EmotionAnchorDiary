import CoreData
import XCTest
@testable import EmotionAnchorDiary

@MainActor
final class LocalDataCleanerTests: XCTestCase {

    /// 删除全部数据：日记、目标和两把密钥都要处理到（PR-12）。
    func testDeleteAllDataRemovesEntriesGoalsAndBothKeys() throws {
        let context = try CoreDataTestSupport.makeInMemoryContext()
        _ = try CoreDataTestSupport.makeEntry(in: context, text: "第一条日记")
        _ = try CoreDataTestSupport.makeEntry(in: context, text: "第二条日记")
        let goalManager = GoalManager(context: context)
        _ = try goalManager.createGoal(title: "每天散步", keywords: ["散步"], targetFrequency: 3)

        var encryptionKeyDeletions = 0
        var apiKeyDeletions = 0
        let cleaner = LocalDataCleaner(
            context: context,
            deleteEncryptionKey: { encryptionKeyDeletions += 1 },
            deleteAPIKey: { apiKeyDeletions += 1 }
        )

        let outcome = try cleaner.deleteAllData()

        XCTAssertEqual(outcome.removedEntryCount, 2)
        XCTAssertEqual(outcome.removedGoalCount, 1)
        XCTAssertEqual(encryptionKeyDeletions, 1)
        XCTAssertEqual(apiKeyDeletions, 1)
        XCTAssertFalse(outcome.keyCleanupFailed)
        XCTAssertEqual(try context.fetch(Entry.fetchRequest()).count, 0)
        XCTAssertEqual(try context.fetch(Goal.fetchRequest()).count, 0)
    }

    /// 空库也要清密钥，否则换设备后旧密钥会残留。
    func testDeleteAllDataOnEmptyStoreStillClearsBothKeys() throws {
        let context = try CoreDataTestSupport.makeInMemoryContext()
        var encryptionKeyDeletions = 0
        var apiKeyDeletions = 0
        let cleaner = LocalDataCleaner(
            context: context,
            deleteEncryptionKey: { encryptionKeyDeletions += 1 },
            deleteAPIKey: { apiKeyDeletions += 1 }
        )

        let outcome = try cleaner.deleteAllData()

        XCTAssertEqual(outcome.removedEntryCount, 0)
        XCTAssertEqual(outcome.removedGoalCount, 0)
        XCTAssertEqual(encryptionKeyDeletions, 1)
        XCTAssertEqual(apiKeyDeletions, 1)
    }

    /// Keychain 清理失败时，界面数据已经删掉，但要如实告知用户密钥没清干净。
    func testDeleteAllDataReportsKeychainFailureWithoutHidingDataRemoval() throws {
        let context = try CoreDataTestSupport.makeInMemoryContext()
        _ = try CoreDataTestSupport.makeEntry(in: context, text: "要被删掉的日记")

        enum TestError: Error { case keychainUnavailable }
        let cleaner = LocalDataCleaner(
            context: context,
            deleteEncryptionKey: { () throws -> Void in throw TestError.keychainUnavailable },
            deleteAPIKey: {}
        )

        let outcome = try cleaner.deleteAllData()

        XCTAssertEqual(outcome.removedEntryCount, 1)
        XCTAssertTrue(outcome.keyCleanupFailed)
        XCTAssertFalse(outcome.encryptionKeyDeleted)
        XCTAssertTrue(outcome.apiKeyDeleted)
        XCTAssertEqual(try context.fetch(Entry.fetchRequest()).count, 0, "密钥清理失败不应回滚已删除的日记")
    }

    /// 只删了一把密钥也算清理不完整。
    func testPartialKeyCleanupIsReportedAsFailure() throws {
        let context = try CoreDataTestSupport.makeInMemoryContext()

        enum TestError: Error { case keychainUnavailable }
        let cleaner = LocalDataCleaner(
            context: context,
            deleteEncryptionKey: {},
            deleteAPIKey: { () throws -> Void in throw TestError.keychainUnavailable }
        )

        let outcome = try cleaner.deleteAllData()

        XCTAssertTrue(outcome.encryptionKeyDeleted)
        XCTAssertFalse(outcome.apiKeyDeleted)
        XCTAssertTrue(outcome.keyCleanupFailed)
    }
}
