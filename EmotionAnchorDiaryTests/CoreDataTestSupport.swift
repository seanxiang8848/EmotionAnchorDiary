import CoreData
import XCTest

/// 测试用的一次性 Core Data 栈。
///
/// 单元测试由 App 托管（`TEST_HOST`），所以模型文件在主 bundle 里；
/// 这里用内存型 store，保证测试既不落盘也不互相污染。
enum CoreDataTestSupport {
    /// 建立一个全新的内存上下文。
    static func makeInMemoryContext() throws -> NSManagedObjectContext {
        let model = try managedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    /// 造一条日记。正文这里不做真实加密，够断言“是否被删除/关联”即可。
    @discardableResult
    static func makeEntry(
        in context: NSManagedObjectContext,
        text: String = "测试日记正文",
        moodTag: String = "平静",
        createdAt: Date = Date()
    ) throws -> Entry {
        let entry = Entry(context: context)
        entry.id = UUID()
        entry.createdAt = createdAt
        entry.moodTag = moodTag
        entry.encryptedBody = Data(text.utf8)
        try context.save()
        return entry
    }

    private static func managedObjectModel() throws -> NSManagedObjectModel {
        // 优先找 momd（版本化模型目录），找不到再退回已编译的 mom。
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(forResource: "EmotionAnchorDiary", withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
        }
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(forResource: "EmotionAnchorDiary", withExtension: "mom"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
        }

        throw NSError(
            domain: "CoreDataTestSupport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "找不到 EmotionAnchorDiary 的 Core Data 模型"]
        )
    }
}
