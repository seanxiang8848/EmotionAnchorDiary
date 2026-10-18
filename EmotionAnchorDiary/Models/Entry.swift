import CoreData
import Foundation

@objc(Entry)
public class Entry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var moodTag: String?
    @NSManaged public var aiSummary: String?
    @NSManaged public var encryptedBody: Data?
    @NSManaged public var goals: Set<Goal>?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Entry> {
        NSFetchRequest<Entry>(entityName: "Entry")
    }

    // To-many relationship accessors (manual codegen requires declaring these by hand)
    @objc(addGoalsObject:)
    @NSManaged public func addToGoals(_ value: Goal)

    @objc(removeGoalsObject:)
    @NSManaged public func removeFromGoals(_ value: Goal)
}

/// A small, explicit mood scale used to build a trend from user-selected labels.
struct MoodOption: Identifiable {
    let tag: String
    let score: Double
    var id: String { tag }

    static let all: [MoodOption] = [
        MoodOption(tag: "低落", score: 1),
        MoodOption(tag: "焦虑", score: 2),
        MoodOption(tag: "平静", score: 3),
        MoodOption(tag: "开心", score: 4),
        MoodOption(tag: "有能量", score: 5)
    ]
}
