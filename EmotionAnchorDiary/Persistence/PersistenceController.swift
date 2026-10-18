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
