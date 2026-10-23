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
    ///
    /// 产品规则：**同一篇日记对同一个目标只计一次**。重复关联同一篇日记时
    /// 仍会认为它命中该目标（会一并返回），但不再重复加计数、也不重复挂接，
    /// 因此多次调用是幂等的。
    func associateGoals(with entry: Entry, plainText: String) throws -> [Goal] {
        let goalRequest = Goal.fetchRequest()
        let goals = try context.fetch(goalRequest)

        let lowercasedText = plainText.lowercased()
        var matched: [Goal] = []
        for goal in goals {
            let keywords = goal.keywordList
            guard keywords.contains(where: { lowercasedText.contains($0.lowercased()) }) else { continue }

            matched.append(goal)
            guard !isLinked(goal, to: entry) else { continue }

            entry.addToGoals(goal)
            goal.lastUpdatedAt = Date()
            goal.hits += 1
        }
        try context.save()
        return matched
    }

    /// 判断这篇日记是否已经挂在该目标下，避免重复计数。
    private func isLinked(_ goal: Goal, to entry: Entry) -> Bool {
        guard let linkedGoals = entry.goals as? Set<Goal> else { return false }
        return linkedGoals.contains { $0.id == goal.id }
    }
}
