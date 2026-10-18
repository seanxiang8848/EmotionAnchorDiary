import CoreData
import Foundation

@objc(Goal)
public class Goal: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var keywords: [String]?
    @NSManaged public var targetFrequency: Int16
    /// 日记命中该目标关键词的累计次数，用于进度提示
    @NSManaged public var hits: Int32
    @NSManaged public var lastUpdatedAt: Date?
    @NSManaged public var entries: Set<Entry>?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Goal> {
        NSFetchRequest<Goal>(entityName: "Goal")
    }

    @objc(addEntriesObject:)
    @NSManaged public func addToEntries(_ value: Entry)

    @objc(removeEntriesObject:)
    @NSManaged public func removeFromEntries(_ value: Entry)
}
