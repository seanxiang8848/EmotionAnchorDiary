import CoreData
import Foundation

/// 负责“删除本设备上的一切数据”。
///
/// 两个 Keychain 清理动作通过闭包注入，因此测试可以在不触碰真实钥匙串
/// （开发机或 CI 模拟器）的前提下，验证日记、目标和两把密钥都被处理到。
struct LocalDataCleaner {
    struct Outcome: Equatable {
        let removedEntryCount: Int
        let removedGoalCount: Int
        let encryptionKeyDeleted: Bool
        let apiKeyDeleted: Bool

        /// 只要有一把密钥没删掉，就要如实告诉用户，不能只报成功。
        var keyCleanupFailed: Bool { !encryptionKeyDeleted || !apiKeyDeleted }
    }

    private let context: NSManagedObjectContext
    private let deleteEncryptionKey: () throws -> Void
    private let deleteAPIKey: () throws -> Void

    init(
        context: NSManagedObjectContext,
        deleteEncryptionKey: @escaping () throws -> Void = { try CryptoManager.shared.deleteKey() },
        deleteAPIKey: @escaping () throws -> Void = { try AIKeyStore.delete() }
    ) {
        self.context = context
        self.deleteEncryptionKey = deleteEncryptionKey
        self.deleteAPIKey = deleteAPIKey
    }

    /// 删除全部日记、全部目标，以及加密密钥和 AI 密钥。
    ///
    /// - Throws: 仅在 Core Data 删除本身失败时抛出；Keychain 失败会通过
    ///   ``Outcome/keyCleanupFailed`` 上报，因为此时界面数据确实已经清空。
    func deleteAllData() throws -> Outcome {
        let entries = try context.fetch(Entry.fetchRequest())
        let goals = try context.fetch(Goal.fetchRequest())

        for entry in entries { context.delete(entry) }
        for goal in goals { context.delete(goal) }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        var encryptionKeyDeleted = true
        var apiKeyDeleted = true
        do { try deleteEncryptionKey() } catch { encryptionKeyDeleted = false }
        do { try deleteAPIKey() } catch { apiKeyDeleted = false }

        return Outcome(
            removedEntryCount: entries.count,
            removedGoalCount: goals.count,
            encryptionKeyDeleted: encryptionKeyDeleted,
            apiKeyDeleted: apiKeyDeleted
        )
    }
}
