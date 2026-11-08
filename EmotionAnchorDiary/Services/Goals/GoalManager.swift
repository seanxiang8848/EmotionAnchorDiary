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

    // MARK: - AI 分析结果落地

    /// 把一次 AI 分析落到目标上：语义匹配、补充关键词、修正节奏、抓取新目标。
    ///
    /// 原则是「只做加法，不改标题」：关键词只增不减，周期与目标天数会被夹到合法区间，
    /// 新目标最多建 2 个且会先和已有目标去重。任何一步失败都不会影响日记本身。
    @discardableResult
    func apply(_ analysis: DiaryAnalysis, to entry: Entry) throws -> GoalApplicationResult {
        let allGoals = try fetchGoals()
        var byID: [UUID: Goal] = [:]
        for goal in allGoals {
            if let id = goal.id { byID[id] = goal }
        }

        var created: [Goal] = []
        var updated: [Goal] = []
        var matched: [Goal] = []
        var notes: [String: [String]] = [:]

        func addNote(_ text: String, to goal: Goal) {
            guard let id = goal.id else { return }
            notes[id.uuidString, default: []].append(text)
        }

        // 1. 语义匹配：比关键词更懂「散步 30 分钟」和「走路」是一回事
        for match in analysis.goalMatches where match.confidence >= Self.matchConfidenceFloor {
            guard let goal = byID[match.goalID] else { continue }
            if !isLinked(goal, to: entry) {
                entry.addToGoals(goal)
                goal.lastUpdatedAt = Date()
            }
            if !matched.contains(where: { $0.id == goal.id }) {
                matched.append(goal)
            }
            let evidence = match.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !evidence.isEmpty {
                addNote("AI 关联：\(clip(evidence, 36))", to: goal)
            }
        }

        // 2. 修正已有目标：补关键词、调周期，标题交给用户自己改
        for update in analysis.goalUpdates where update.confidence >= Self.updateConfidenceFloor {
            guard let goal = byID[update.goalID] else { continue }
            var changes: [String] = []

            let previousKeywords = goal.keywordList
            let merged = mergeKeywords(existing: previousKeywords, adding: update.addKeywords)
            if merged.count > previousKeywords.count {
                let added = merged.filter { keyword in
                    !previousKeywords.contains { $0.caseInsensitiveCompare(keyword) == .orderedSame }
                }
                goal.keywordList = merged
                if !added.isEmpty {
                    changes.append("补充关键词：\(added.prefix(3).joined(separator: "、"))")
                }
            }

            var period = goal.effectivePeriodDays
            var target = goal.effectiveTargetDays
            if let proposed = update.periodDays {
                period = min(max(proposed, 1), 30)
            }
            if let proposed = update.targetDays {
                target = max(proposed, 1)
            }
            target = min(target, period)
            if period != goal.effectivePeriodDays || target != goal.effectiveTargetDays {
                changes.append("节奏改为\(Self.ruleText(periodDays: period, targetDays: target))（原：\(goal.goalRuleText)）")
                goal.periodDays = Int16(period)
                goal.targetFrequency = Int16(target)
            }

            guard !changes.isEmpty else { continue }
            goal.lastUpdatedAt = Date()
            if !updated.contains(where: { $0.id == goal.id }) {
                updated.append(goal)
            }
            for change in changes {
                addNote(change, to: goal)
            }
        }

        // 3. 抓取新目标：先查重，再创建，最多 2 个
        var knownGoals = allGoals
        knownGoals.append(contentsOf: updated)

        for candidate in analysis.newGoals where candidate.confidence >= Self.newGoalConfidenceFloor {
            guard created.count < 2 else { break }
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            if let duplicate = findDuplicate(title: title, keywords: candidate.keywords, in: knownGoals) {
                if !isLinked(duplicate, to: entry) {
                    entry.addToGoals(duplicate)
                }
                let merged = mergeKeywords(existing: duplicate.keywordList, adding: candidate.keywords)
                if merged.count > duplicate.keywordList.count {
                    duplicate.keywordList = merged
                }
                duplicate.lastUpdatedAt = Date()
                if !matched.contains(where: { $0.id == duplicate.id }) {
                    matched.append(duplicate)
                }
                addNote("AI 判定与已有目标重复，已并入", to: duplicate)
                continue
            }

            let period = min(max(candidate.periodDays, 1), 30)
            let target = min(max(candidate.targetDays, 1), period)
            guard let goal = try? createGoal(
                title: title,
                keywords: candidate.keywords,
                targetFrequency: Int16(target),
                periodDays: Int16(period)
            ) else { continue }

            entry.addToGoals(goal)
            created.append(goal)
            knownGoals.append(goal)
            addNote("AI 新建目标", to: goal)
        }

        try context.save()

        var ordered: [Goal] = []
        for goal in created + updated + matched where !ordered.contains(where: { $0.id == goal.id }) {
            ordered.append(goal)
        }
        return GoalApplicationResult(goals: ordered, notes: notes)
    }

    private static let matchConfidenceFloor = 0.55
    private static let updateConfidenceFloor = 0.6
    private static let newGoalConfidenceFloor = 0.7

    private static func ruleText(periodDays: Int, targetDays: Int) -> String {
        "最近 \(periodDays) 天内完成 \(targetDays) 天"
    }

    private func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    /// 只增不减地合并关键词，最多保留 12 个。
    private func mergeKeywords(existing: [String], adding: [String]) -> [String] {
        var result = existing
        var seen = Set(existing.map { $0.lowercased() })
        for keyword in adding {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key), result.count < 12 else { continue }
            result.append(trimmed)
            seen.insert(key)
        }
        return result
    }

    /// 标题相同、互相包含，或关键词高度重叠，都算重复目标。
    private func findDuplicate(title: String, keywords: [String], in goals: [Goal]) -> Goal? {
        let normalized = normalizeTitle(title)
        guard !normalized.isEmpty else { return nil }
        let candidateKeywords = Set(keywords.map { $0.lowercased() })

        for goal in goals {
            let existing = normalizeTitle(goal.title ?? "")
            if !existing.isEmpty, existing == normalized {
                return goal
            }
            if existing.count >= 2, normalized.count >= 2,
               existing.contains(normalized) || normalized.contains(existing) {
                return goal
            }
            if candidateKeywords.count >= 2 {
                let existingKeywords = Set(goal.keywordList.map { $0.lowercased() })
                if existingKeywords.intersection(candidateKeywords).count >= 2 {
                    return goal
                }
            }
        }
        return nil
    }

    private func normalizeTitle(_ title: String) -> String {
        title.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }
}

/// 一次 AI 分析对目标产生的动作汇总，供界面展示。
struct GoalApplicationResult {
    /// 本次涉及的目标（新建 → 修正 → 匹配），已按优先级去重。
    var goals: [Goal] = []
    /// 每个目标的变更说明，key 是 goal.id.uuidString。
    var notes: [String: [String]] = [:]
}
