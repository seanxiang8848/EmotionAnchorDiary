import CoreData
import Foundation

/// Manages CRUD operations for goals and handles keyword linking to entries for progress tracking.
@MainActor
final class GoalManager {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// 新建一个目标。
    /// - Parameters:
    ///   - targetFrequency: 周期内需要完成的**天数**（例如 3 表示「7 天内完成 3 天」）。
    ///   - periodDays: 时间窗口天数，包含今天（例如 7 表示「最近 7 天」）。
    func createGoal(
        title: String,
        keywords: [String],
        targetFrequency: Int16,
        periodDays: Int16 = 7
    ) throws -> Goal {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(cleanTitle: cleanTitle, targetFrequency: targetFrequency, periodDays: periodDays) else {
            throw NSError(domain: "GoalManager", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.invalidInputMessage])
        }
        let goal = Goal(context: context)
        goal.id = UUID()
        goal.title = cleanTitle
        goal.keywordList = normalizedKeywords(keywords)
        goal.targetFrequency = targetFrequency
        goal.periodDays = periodDays
        goal.lastUpdatedAt = Date()

        try context.save()
        return goal
    }

    func updateGoal(
        _ goal: Goal,
        title: String,
        keywords: [String],
        targetFrequency: Int16,
        periodDays: Int16
    ) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(cleanTitle: cleanTitle, targetFrequency: targetFrequency, periodDays: periodDays) else {
            throw NSError(domain: "GoalManager", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.invalidInputMessage])
        }
        goal.title = cleanTitle
        goal.keywordList = normalizedKeywords(keywords)
        goal.targetFrequency = targetFrequency
        goal.periodDays = periodDays
        goal.lastUpdatedAt = Date()
        try context.save()
    }

    private static let invalidInputMessage = "目标名称和周期天数必须有效，且目标天数不能超过周期天数"

    /// 目标天数必须落在 [1, periodDays] 内，周期至少 1 天。
    private func isValid(cleanTitle: String, targetFrequency: Int16, periodDays: Int16) -> Bool {
        !cleanTitle.isEmpty && periodDays >= 1 && targetFrequency >= 1 && targetFrequency <= periodDays
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
    /// 这里只负责建立「日记 ↔ 目标」的挂接关系；进度不再存成累计计数，而是
    /// 由 ``Goal/completedDays(referenceDate:calendar:)`` 按「周期内的不同天数」
    /// 实时算出来，因此删掉日记或时间过期后进度会自然回落。
    ///
    /// 产品规则：**同一篇日记对同一个目标只挂接一次**。重复调用是幂等的，
    /// 仍会返回命中的目标，但不会重复挂接。
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
        }
        try context.save()
        return matched
    }

    /// 判断这篇日记是否已经挂在该目标下。
    private func isLinked(_ goal: Goal, to entry: Entry) -> Bool {
        guard let linkedGoals = entry.goals as? Set<Goal> else { return false }
        return linkedGoals.contains { $0.id == goal.id }
    }
}
