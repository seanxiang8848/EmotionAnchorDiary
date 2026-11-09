import Combine
import CoreData
import Foundation

@MainActor
final class DiaryEntryViewModel: ObservableObject {
    struct FeedbackBanner {
        let message: String
        let isError: Bool
    }

    struct GoalProgressSnapshot: Identifiable {
        let id: UUID
        let title: String
        /// AI 本次对该目标做了什么（关联 / 补关键词 / 改节奏 / 新建）。
        let note: String?
        /// 周期内已完成的天数（同一天写多篇只算一天）。
        let completedDays: Int
        /// 周期内需要完成的天数。
        let targetDays: Int

        var progressValue: Double {
            guard targetDays > 0 else { return 1 }
            return min(1, Double(completedDays) / Double(targetDays))
        }
    }

    /// 这一次结果是云端 AI 给的，还是本地兜底文案。
    enum AnalysisSource: Equatable {
        case cloud(provider: String, model: String, characters: Int)
        case local(reason: String?)

        var badge: String {
            switch self {
            case let .cloud(provider, model, characters):
                return "\(provider) · \(model) · 摘要 \(characters) 字"
            case .local:
                return "本地文案"
            }
        }

        var failureReason: String? {
            if case let .local(reason) = self { return reason }
            return nil
        }

        var isCloud: Bool {
            if case .cloud = self { return true }
            return false
        }
    }

    @Published var journalText: String = ""
    @Published var selectedMoodTag: String = "平静"
    @Published var isProcessing: Bool = false
    @Published var feedbackBanner: FeedbackBanner? = nil
    @Published var analysis: DiaryAnalysis? = nil
    @Published var analysisSource: AnalysisSource = .local(reason: nil)
    @Published var goalSnapshots: [GoalProgressSnapshot] = []
    @Published var isRecording: Bool = false
    @Published var isAIReady: Bool = false

    private let context: NSManagedObjectContext
    private let persistence: PersistenceController
    private let goalManager: GoalManager
    private let aiService: DiaryAIService?
    private let speechService: SpeechService
    private let bannerDismissDelay: TimeInterval = 3

    var viewContext: NSManagedObjectContext { context }

    init(
        context: NSManagedObjectContext,
        persistence: PersistenceController = .shared,
        goalManager: GoalManager? = nil,
        aiService: DiaryAIService? = nil,
        speechService: SpeechService? = nil
    ) {
        self.context = context
        self.persistence = persistence
        self.goalManager = goalManager ?? GoalManager(context: context)
        self.aiService = aiService
        self.speechService = speechService ?? SpeechService()
        self.isAIReady = aiService?.hasAPIKey ?? false
        bindSpeechTranscript()
    }

    func handleSubmit() {
        Task {
            await submitEntry()
        }
    }

    func refreshAIStatus() {
        isAIReady = aiService?.hasAPIKey ?? false
    }

    /// 设置页「保存并测试连接」用。
    func testAIConnection() async throws -> String {
        guard let service = aiService else { throw AIServiceError.notConfigured }
        return try await service.testConnection()
    }

    func toggleRecording() {
        Task {
            if isRecording {
                speechService.stopRecording()
            } else {
                await speechService.requestAuthorization()
                guard speechService.authorizationStatus == .authorized else {
                    isRecording = false
                    feedbackBanner = .init(message: "语音未获授权，请允许麦克风和语音识别后重试", isError: true)
                    autoDismissBanner()
                    return
                }

                do {
                    // 新一轮录音从空白开始。转写绑定现在会过滤空串，
                    // 所以清屏动作改在这里显式完成，语义与旧版一致。
                    journalText = ""
                    try speechService.startRecording()
                } catch {
                    isRecording = false
                    feedbackBanner = .init(message: "语音启用失败，请检查权限", isError: true)
                    autoDismissBanner()
                }
            }
            isRecording = speechService.isRecording
        }
    }

    private func bindSpeechTranscript() {
        // 只把「真正有内容的转写结果」写进编辑框。
        // 旧写法直接 assign 全部值：startRecording 的初始空串、识别回调里的
        // 空结果都会写回 journalText，在录音与手动输入交错时会把刚键入的文字
        // 瞬间清掉（真机反馈「看不见已键入内容」的另一条路径）。
        speechService.$transcript
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .assign(to: &$journalText)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
    }

    private func sanitizeText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 保存并分析

    func submitEntry() async {
        let cleanText = sanitizeText(journalText)
        guard !cleanText.isEmpty else {
            feedbackBanner = .init(message: "请填写内容后再提交", isError: true)
            autoDismissBanner()
            return
        }
        guard !isProcessing else { return }

        isProcessing = true
        analysis = nil
        goalSnapshots = []
        defer { isProcessing = false }

        do {
            // 先落盘再分析：即使网络失败，日记也不会丢。
            let entry = try persistence.createEntry(text: cleanText, moodTag: selectedMoodTag)
            let keywordMatches = (try? goalManager.associateGoals(with: entry, plainText: cleanText)) ?? []

            let cloudAnalysisAllowed = UserDefaults.standard.bool(forKey: "allowCloudAnalysis")
            if cloudAnalysisAllowed, let service = aiService {
                await runCloudAnalysis(
                    text: cleanText,
                    entry: entry,
                    keywordMatches: keywordMatches,
                    service: service
                )
            } else {
                applyLocalResult(moodTag: selectedMoodTag, goals: keywordMatches, reason: nil)
                feedbackBanner = .init(message: "已保存并使用本地安慰文案", isError: false)
            }

            journalText = ""
        } catch {
            feedbackBanner = .init(message: "保存失败，请稍后重试", isError: true)
        }

        autoDismissBanner()
    }

    /// 云端分析：只发摘要 + 目标结构，拿到情绪、共情与目标动作后落地。
    private func runCloudAnalysis(
        text: String,
        entry: Entry,
        keywordMatches: [Goal],
        service: DiaryAIService
    ) async {
        let summary = LocalDiarySummarizer.summarize(text)
        let goals = (try? goalManager.fetchGoals())?.compactMap { $0.aiContext } ?? []

        do {
            let result = try await service.analyze(
                summary: summary,
                moodTag: selectedMoodTag,
                recentMoods: recentMoodTags(),
                goals: goals
            )
            try store(result, summary: summary, on: entry)

            analysis = result
            analysisSource = .cloud(
                provider: service.providerName,
                model: service.modelName,
                characters: summary.count
            )

            // 目标落地失败不应该把已经拿到的情绪卡也一起丢掉。
            do {
                let application = try goalManager.apply(result, to: entry)
                goalSnapshots = makeSnapshots(
                    goals: merged(application.goals, keywordMatches),
                    notes: application.notes
                )
            } catch {
                goalSnapshots = makeSnapshots(goals: keywordMatches, notes: [:])
            }

            isAIReady = true
            feedbackBanner = .init(message: "已保存 · AI 已完成情绪与目标分析", isError: false)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            applyLocalResult(moodTag: selectedMoodTag, goals: keywordMatches, reason: reason)
            feedbackBanner = .init(message: "已保存并使用本地安慰文案", isError: false)
        }
    }

    private func store(_ analysis: DiaryAnalysis, summary: String, on entry: Entry) throws {
        entry.aiSummary = summary
        entry.aiAnalysisJSON = analysis.storageJSON
        entry.aiAnalyzedAt = Date()
        try context.save()
    }

    private func applyLocalResult(moodTag: String, goals: [Goal], reason: String?) {
        analysis = LocalEmpathy.analysis(moodTag: moodTag)
        analysisSource = .local(reason: reason)
        goalSnapshots = makeSnapshots(goals: goals, notes: [:])
    }

    private func makeSnapshots(goals: [Goal], notes: [String: [String]]) -> [GoalProgressSnapshot] {
        goals.compactMap { goal in
            guard let id = goal.id else { return nil }
            let note = notes[id.uuidString]?.joined(separator: " · ")
            return GoalProgressSnapshot(
                id: id,
                title: goal.title ?? "未命名目标",
                note: (note?.isEmpty ?? true) ? nil : note,
                completedDays: goal.completedDays(),
                targetDays: goal.effectiveTargetDays
            )
        }
    }

    private func merged(_ primary: [Goal], _ secondary: [Goal]) -> [Goal] {
        var result = primary
        for goal in secondary where !result.contains(where: { $0.id == goal.id }) {
            result.append(goal)
        }
        return result
    }

    /// 取最近几篇的心情标签，给 AI 一点趋势上下文。
    private func recentMoodTags(limit: Int = 3) -> [String] {
        let request = Entry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: false)]
        request.fetchLimit = limit
        guard let entries = try? context.fetch(request) else { return [] }
        return entries.compactMap { $0.moodTag }.filter { !$0.isEmpty }
    }

    private func autoDismissBanner() {
        let shouldAutoDismiss = !(feedbackBanner?.isError ?? false)
        guard shouldAutoDismiss else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bannerDismissDelay * 1_000_000_000))
            if !isProcessing {
                feedbackBanner = nil
            }
        }
    }
}
