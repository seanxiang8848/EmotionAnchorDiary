import CoreData
import Foundation

/// Manages CRUD operations for goals and handles keyword linking to entries for progress tracking.
@MainActor
final class GoalManager {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func createGoal(title: String, keywords: [String], targetFrequency: Int16) throws -> Goal {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, targetFrequency > 0 else {
            throw NSError(domain: "GoalManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "目标名称和周期次数必须有效"])
        }
        let goal = Goal(context: context)
        goal.id = UUID()
        goal.title = cleanTitle
        goal.keywordList = normalizedKeywords(keywords)
        goal.targetFrequency = targetFrequency
        goal.lastUpdatedAt = Date()

        try context.save()
        return goal
    }

    func updateGoal(_ goal: Goal, title: String, keywords: [String], targetFrequency: Int16) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, targetFrequency > 0 else {
            throw NSError(domain: "GoalManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "目标名称和周期次数必须有效"])
        }
        goal.title = cleanTitle
        goal.keywordList = normalizedKeywords(keywords)
        goal.targetFrequency = targetFrequency
        goal.lastUpdatedAt = Date()
        try context.save()
    }

    func deleteGoal(_ goal: Goal) throws {
        context.delete(goal)
        try context.save()
    }

    private func normalizedKeywords(_ keywords: [String]) -> [String] {
        Array(Set(keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    }

    func fetchGoals() throws -> [Goal] {
        let request = Goal.fetchRequest()
        return try context.fetch(request)
    }

    /// Performs a naive keyword scan on entry text and associates matching goals, returning matches for UI progress hints.
    func associateGoals(with entry: Entry, plainText: String) throws -> [Goal] {
        let goalRequest = Goal.fetchRequest()
        let goals = try context.fetch(goalRequest)

        let lowercasedText = plainText.lowercased()
        var matched: [Goal] = []
        for goal in goals {
            let keywords = goal.keywordList
            if keywords.contains(where: { lowercasedText.contains($0.lowercased()) }) {
                entry.addToGoals(goal)
                goal.lastUpdatedAt = Date()
                goal.hits += 1
                matched.append(goal)
            }
        }
        try context.save()
        return matched
    }
}
