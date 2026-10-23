import CoreData
import Foundation

/// Coordinates the Core Data stack and injects the encryption layer before touching disk.
struct PersistenceController {
    static let shared = PersistenceController(
        inMemory: ProcessInfo.processInfo.arguments.contains("-ui-testing")
    )

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "EmotionAnchorDiary")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        // 目标模型加了周期字段、移除了旧的累计计数字段，显式打开轻量迁移，
        // 避免旧版本装过的设备打不开。
        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data store: \(error.localizedDescription)")
            }
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Persists a diary entry after encrypting the sensitive text.
    @discardableResult
    func createEntry(text: String, moodTag: String?) throws -> Entry {
        let context = container.viewContext
        let entry = Entry(context: context)
        entry.id = UUID()
        entry.createdAt = Date()
        entry.moodTag = moodTag
        entry.aiSummary = nil
        entry.encryptedBody = try CryptoManager.shared.encrypt(text)

        try context.save()
        return entry
    }
}
