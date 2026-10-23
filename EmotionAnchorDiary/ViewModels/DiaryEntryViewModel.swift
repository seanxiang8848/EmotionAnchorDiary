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
        /// 周期内已完成的天数（同一天写多篇只算一天）。
        let completedDays: Int
        /// 周期内需要完成的天数。
        let targetDays: Int

        var progressValue: Double {
            guard targetDays > 0 else { return 1 }
            return min(1, Double(completedDays) / Double(targetDays))
        }
    }

    @Published var journalText: String = ""
    @Published var selectedMoodTag: String = "平静"
    @Published var isProcessing: Bool = false
    @Published var alertMessage: String? = nil
    @Published var feedbackBanner: FeedbackBanner? = nil
    @Published var empathyCard: EmpathyCard? = nil
    @Published var matchedGoals: [Goal] = []
    @Published var goalSnapshots: [GoalProgressSnapshot] = []
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var waveformSamples: [Double] = []

    private let context: NSManagedObjectContext
    private let persistence: PersistenceController
    private let goalManager: GoalManager
    private let emotionService: EmotionCoachService?
    private let speechService: SpeechService
    private let bannerDismissDelay: TimeInterval = 2.5

    var viewContext: NSManagedObjectContext { context }

    init(
        context: NSManagedObjectContext,
        persistence: PersistenceController = .shared,
        goalManager: GoalManager? = nil,
        emotionService: EmotionCoachService? = nil,
        speechService: SpeechService? = nil
    ) {
        self.context = context
        self.persistence = persistence
        self.goalManager = goalManager ?? GoalManager(context: context)
        self.emotionService = emotionService
        self.speechService = speechService ?? SpeechService()
        bindSpeechTranscript()
        waveformSamples = Array(repeating: 0.3, count: 12)
    }

    func handleSubmit() {
        Task {
            await submitEntry()
        }
    }

    func toggleRecording() {
        Task {
            if isRecording {
                speechService.stopRecording()
            } else {
                recordingDuration = 0
                await speechService.requestAuthorization()
                guard speechService.authorizationStatus == .authorized else {
                    isRecording = false
                    feedbackBanner = .init(message: "语音未获授权，请允许麦克风和语音识别后重试", isError: true)
                    autoDismissBanner()
                    return
                }

                do {
                    try speechService.startRecording()
                    waveformSamples = randomWaveform()
                    scheduleRecordingTimer()
                } catch {
                    isRecording = false
                    feedbackBanner = .init(message: "语音启用失败，请检查权限", isError: true)
                    autoDismissBanner()
                }
            }
            isRecording = speechService.isRecording
        }
    }

    private func scheduleRecordingTimer() {
        Task { [weak self] in
            while let self, self.isRecording {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if self.isRecording {
                        self.recordingDuration += 1
                        self.waveformSamples = self.randomWaveform()
                    }
                }
            }
        }
    }

    private func randomWaveform() -> [Double] {
        (0..<12).map { _ in Double.random(in: 0.2...0.9) }
    }

    private func bindSpeechTranscript() {
        speechService.$transcript
            .receive(on: DispatchQueue.main)
            .assign(to: &$journalText)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
    }

    private func sanitizeText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func submitEntry() async {
        let cleanText = sanitizeText(journalText)
        guard !cleanText.isEmpty else {
            feedbackBanner = .init(message: "请填写内容后再提交", isError: true)
            autoDismissBanner()
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let entry = try persistence.createEntry(text: cleanText, moodTag: selectedMoodTag)
            let matched = try goalManager.associateGoals(with: entry, plainText: cleanText)
            matchedGoals = matched
            goalSnapshots = matched.compactMap { goal in
                guard let id = goal.id else { return nil }
                // 进度按「周期内完成的天数」实时算，不存累计计数
                return GoalProgressSnapshot(
                    id: id,
                    title: goal.title ?? "未命名目标",
                    completedDays: goal.completedDays(),
                    targetDays: goal.effectiveTargetDays
                )
            }

            var usedFallback = false
            let cloudAnalysisAllowed = UserDefaults.standard.bool(forKey: "allowCloudAnalysis")
            if cloudAnalysisAllowed, let emotionService {
                do {
                    let localSummary = LocalDiarySummarizer.summarize(cleanText)
                    empathyCard = try await emotionService.fetchEmpathyCard(summary: localSummary)
                } catch {
                    usedFallback = true
                    empathyCard = EmotionCoachService.fallbackCard()
                }
            } else {
                usedFallback = true
                empathyCard = EmotionCoachService.fallbackCard()
            }

            journalText = ""
            feedbackBanner = .init(
                message: usedFallback ? "已保存并使用本地安慰文案" : "已保存并加密，已完成 AI 分析",
                isError: false
            )
        } catch {
            feedbackBanner = .init(message: "保存失败，请稍后重试", isError: true)
        }

        autoDismissBanner()
    }

    private func autoDismissBanner() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bannerDismissDelay * 1_000_000_000))
            if !isProcessing {
                feedbackBanner = nil
            }
        }
    }
}
