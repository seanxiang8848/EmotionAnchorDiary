import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct DiaryEntryView: View {
    @ObservedObject var viewModel: DiaryEntryViewModel
    @State private var showSavedEntries: Bool = false
    @FocusState private var isJournalFocused: Bool
    @AppStorage("allowCloudAnalysis") private var allowCloudAnalysis = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let banner = viewModel.feedbackBanner {
                        Text(banner.message)
                            .font(.footnote)
                            .foregroundColor(banner.isError ? .red : .green)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(banner.isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                    Text("今天的心情在哪儿？")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack {
                        Button("查看历史条目") {
                            showSavedEntries.toggle()
                        }
                        NavigationLink("目标追踪") {
                            GoalDashboardView()
                                .environment(\.managedObjectContext, viewModel.viewContext)
                        }
                        NavigationLink("心情趋势") {
                            MoodTrendView()
                                .environment(\.managedObjectContext, viewModel.viewContext)
                        }
                    }
                    .font(.subheadline)

                    TextEditor(text: $viewModel.journalText)
                        // minHeight + maxHeight：固定 height 的 TextEditor 在 ScrollView 里
                        // 有已知渲染缺陷（输入到中途光标前的内容“消失”，滚动后才复现）
                        .frame(minHeight: 160, maxHeight: 320)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                        .focused($isJournalFocused)
                        .accessibilityIdentifier("diary-entry-editor")

                    Picker("此刻的心情", selection: $viewModel.selectedMoodTag) {
                        ForEach(MoodOption.all) { mood in
                            Text(mood.tag).tag(mood.tag)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("允许 AI 云端分析", isOn: $allowCloudAnalysis)
                        Text(allowCloudAnalysis
                             ? "开启后只发送本机提取的摘要（最多 3 句、300 字）与目标结构，不发送完整日记正文。"
                             : "关闭时，日记仅保存在本机，并使用本地共情文案。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if allowCloudAnalysis && !viewModel.isAIReady {
                            Text("还没有配置 API Key。点右上角齿轮 → AI 服务，选 DeepSeek 填 Key 就能接管情绪与目标分析。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: viewModel.toggleRecording) {
                                Label(viewModel.isRecording ? "停止录音" : "语音记录", systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(viewModel.isRecording ? Color.red.opacity(0.8) : Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }

                            if viewModel.isRecording {
                                // 计时与波形由子视图自持：每秒重渲染只发生在这个小组件里，
                                // 不会触发整页（含 TextEditor）重算
                                RecordingIndicatorView()
                            }
                        }

                        Button(action: {
                            isJournalFocused = false
                            viewModel.handleSubmit()
                        }) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("保存并生成共情")
                                    .padding()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .background(viewModel.isProcessing ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(viewModel.isProcessing)
                    }

                    if viewModel.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("正在读取情绪与目标…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let analysis = viewModel.analysis {
                        AnalysisCardView(
                            analysis: analysis,
                            badge: viewModel.analysisSource.badge,
                            note: viewModel.analysisSource.failureReason
                        )
                    }

                    if !viewModel.goalSnapshots.isEmpty {
                        GoalInsightCard(snapshots: viewModel.goalSnapshots)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("情绪锚点")
            .onAppear { viewModel.refreshAIStatus() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isJournalFocused = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AppSettingsView(viewModel: viewModel)) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
        .sheet(isPresented: $showSavedEntries) {
            EntryListView()
                .environment(\.managedObjectContext, viewModel.viewContext)
        }
    }
}

// MARK: - AI 情绪卡

/// 情绪解读 + 共情回应 + 建议。历史详情页也复用这张卡。
struct AnalysisCardView: View {
    let analysis: DiaryAnalysis
    let badge: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("情绪解读", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text(analysis.emotion.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(emotionColor.opacity(0.16))
                    .foregroundColor(emotionColor)
                    .clipShape(Capsule())
                Text("\(analysis.emotion.score, specifier: "%.1f") / 5")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(intensityText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(analysis.empathy)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if !analysis.emotion.reason.isEmpty {
                Text("判断依据：\(analysis.emotion.reason)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !analysis.suggestions.isEmpty {
                Divider()
                Text("可以试试")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(analysis.suggestions, id: \.self) { suggestion in
                    Text("• \(suggestion)")
                        .font(.subheadline)
                }
            }

            if let note = note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var emotionColor: Color {
        switch analysis.emotion.label {
        case "低落": return .gray
        case "焦虑": return .orange
        case "开心": return .yellow
        case "有能量": return .green
        default: return .blue
        }
    }

    private var intensityText: String {
        switch analysis.emotion.intensity {
        case ..<0.35: return "强度：轻"
        case ..<0.7: return "强度：中"
        default: return "强度：强"
        }
    }
}

// MARK: - 目标动向卡

private struct GoalInsightCard: View {
    let snapshots: [DiaryEntryViewModel.GoalProgressSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("目标动向", systemImage: "scope")
                .font(.headline)

            ForEach(snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(snapshot.completedDays)/\(snapshot.targetDays) 天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: snapshot.progressValue)
                        .progressViewStyle(.linear)
                    if let note = snapshot.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.06))
        .cornerRadius(12)
    }
}

/// 录音中的计时 + 波形指示。
///
/// 每秒刷新只发生在这个子视图内部（自持 Timer 与状态），
/// 不再通过 ViewModel 的 @Published 触发整页重渲染——
/// 否则手动输入日记时每秒钟页面重算会让 TextEditor 的光标/内容显示异常。
private struct RecordingIndicatorView: View {
    @State private var elapsedSeconds: Int = 0
    @State private var samples: [Double] = Array(repeating: 0.3, count: 12)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("录音中：\(elapsedSeconds)s")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: 4, height: CGFloat(20 + sample * 40))
                }
            }
            .frame(height: 40)
        }
        .onReceive(timer) { _ in
            elapsedSeconds += 1
            samples = (0..<12).map { _ in Double.random(in: 0.2...0.9) }
        }
    }
}

// MARK: - 设置

struct AppSettingsView: View {
    @ObservedObject var viewModel: DiaryEntryViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var provider: AIProvider = APIConfig.current().provider
    @State private var baseURLText: String = APIConfig.current().baseURL.absoluteString
    @State private var modelText: String = APIConfig.current().model
    @State private var apiKey: String = AIKeyStore.load() ?? ""
    @State private var isTestingConnection = false
    @State private var aiStatusMessage: String?
    @State private var aiStatusIsError = false

    @State private var statusMessage: String?
    @State private var showMessage = false
    @State private var isExporting = false
    @State private var exportDocument = DiaryExportDocument(text: "")
    @State private var confirmDeleteAll = false
    @AppStorage("requireAppUnlock") private var requireAppUnlock = false
    @AppStorage("allowCloudAnalysis") private var allowCloudAnalysis = false

    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    var body: some View {
        Form {
            Section("AI 服务") {
                Picker("服务商", selection: $provider) {
                    ForEach(AIProvider.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .onChange(of: provider) { newValue in
                    guard newValue != .custom else { return }
                    baseURLText = newValue.defaultBaseURL
                    modelText = newValue.defaultModel
                }

                TextField("模型", text: $modelText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("API 地址（https）", text: $baseURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveAndTestConnection()
                } label: {
                    HStack(spacing: 6) {
                        if isTestingConnection {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(isTestingConnection ? "正在测试连接…" : "保存并测试连接")
                    }
                }
                .disabled(isTestingConnection)

                Toggle("保存日记时使用 AI 分析", isOn: $allowCloudAnalysis)

                if let status = aiStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(aiStatusIsError ? .red : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("密钥只保存在本机钥匙串。\(provider.keyHint)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("删除本机 API Key", role: .destructive) {
                    deleteAPIKey()
                }
            }

            Section("隐私") {
                Toggle("启动时使用 Face ID 或设备密码", isOn: $requireAppUnlock)
                    .accessibilityIdentifier("app-lock-toggle")
                Text("AI 云端分析默认关闭。开启后，应用会先在本机提取摘要（最多 3 句、300 字）再发送，完整日记仍只保存在本机；关闭或失败时使用本地共情文案。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("导出日记") {
                    prepareExport()
                }
                Button("删除所有本地日记和目标…", role: .destructive) {
                    confirmDeleteAll = true
                }
            }
        }
        .navigationTitle("设置")
        .alert(statusMessage ?? "", isPresented: $showMessage) {
            Button("好", role: .cancel) { }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "EmotionAnchorDiary-Export"
        ) { result in
            switch result {
            case .success:
                statusMessage = "日记已导出。"
                showMessage = true
            case .failure(let error) where (error as? CocoaError)?.code == .userCancelled:
                break
            case .failure:
                statusMessage = "导出失败，请检查存储位置后重试。"
                showMessage = true
            }
        }
        .confirmationDialog("删除全部日记和目标？此操作无法撤销。", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("删除全部数据", role: .destructive, action: deleteAllData)
            Button("取消", role: .cancel) { }
        }
    }

    private func saveAndTestConnection() {
        guard let config = APIConfig.validated(provider: provider, baseURLString: baseURLText, model: modelText) else {
            aiStatusIsError = true
            aiStatusMessage = "请检查：API 地址必须是 https，模型名不能为空。"
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            aiStatusIsError = true
            aiStatusMessage = "请先填写 API Key。"
            return
        }

        isTestingConnection = true
        aiStatusIsError = false
        aiStatusMessage = "正在连接 \(config.provider.displayName)…"

        Task { @MainActor in
            do {
                try AIKeyStore.save(key)
                APIConfig.save(config)
                let reply = try await viewModel.testAIConnection()
                isTestingConnection = false
                aiStatusIsError = false
                aiStatusMessage = allowCloudAnalysis
                    ? "连接成功：\(config.model) 回复「\(reply)」。之后保存日记就会自动分析。"
                    : "连接成功：\(config.model) 回复「\(reply)」。打开上面的开关后开始分析。"
                viewModel.refreshAIStatus()
            } catch {
                isTestingConnection = false
                aiStatusIsError = true
                aiStatusMessage = error.localizedDescription
                viewModel.refreshAIStatus()
            }
        }
    }

    private func deleteAPIKey() {
        do {
            try AIKeyStore.delete()
            APIConfig.clear()
            apiKey = ""
            provider = APIConfig.current().provider
            baseURLText = APIConfig.current().baseURL.absoluteString
            modelText = APIConfig.current().model
            viewModel.refreshAIStatus()
            aiStatusIsError = false
            aiStatusMessage = "API Key 已删除，之后使用本地共情文案。"
        } catch {
            aiStatusIsError = true
            aiStatusMessage = "删除失败，请稍后重试。"
        }
    }

    private func prepareExport() {
        do {
            let request = Entry.fetchRequest()
            let entries = try context.fetch(request)
            guard !entries.isEmpty else {
                statusMessage = "暂无日记可导出。"
                showMessage = true
                return
            }

            let exportEntries = entries.map {
                DiaryExportEntry(createdAt: $0.createdAt, moodTag: $0.moodTag, encryptedBody: $0.encryptedBody)
            }
            let text = try DiaryExportFormatter.render(exportEntries) {
                try CryptoManager.shared.decrypt($0)
            }
            exportDocument = DiaryExportDocument(text: text)
            isExporting = true
        } catch {
            statusMessage = "读取或解密日记失败，未生成导出文件。"
            showMessage = true
        }
    }

    private func deleteAllData() {
        // UI 测试下换成空操作，避免动到模拟器/开发机的真实 Keychain。
        let cleaner: LocalDataCleaner
        if isUITesting {
            cleaner = LocalDataCleaner(context: context, deleteEncryptionKey: {}, deleteAPIKey: {})
        } else {
            cleaner = LocalDataCleaner(
                context: context,
                deleteEncryptionKey: { try CryptoManager.shared.deleteKey() },
                deleteAPIKey: { try AIKeyStore.delete() }
            )
        }

        do {
            let outcome = try cleaner.deleteAllData()

            allowCloudAnalysis = false
            APIConfig.clear()
            apiKey = ""
            viewModel.journalText = ""
            viewModel.analysis = nil
            viewModel.goalSnapshots = []
            viewModel.refreshAIStatus()
            statusMessage = outcome.keyCleanupFailed
                ? "日记和目标已删除，但 Keychain 清理未能完整完成。"
                : "本机日记、目标和 AI 密钥已删除。"
        } catch {
            statusMessage = "删除本地数据失败，请重试。"
        }
        showMessage = true
    }
}

struct DiaryExportEntry {
    let createdAt: Date?
    let moodTag: String?
    let encryptedBody: Data?
}

enum DiaryExportFormatter {
    static func render(
        _ entries: [DiaryExportEntry],
        decrypt: (Data) throws -> String
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        let sortedEntries = entries.sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }

        let blocks = try sortedEntries.map { entry -> String in
            guard let encryptedBody = entry.encryptedBody else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let body = try decrypt(encryptedBody)
            let date = formatter.string(from: entry.createdAt ?? Date())
            return "\(date)  心情：\(entry.moodTag ?? "未记录")\n\(body)"
        }
        return blocks.joined(separator: "\n\n---\n\n")
    }
}

struct DiaryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: serializedData)
    }

    var serializedData: Data { Data(text.utf8) }
}

#Preview {
    DiaryEntryView(viewModel: DiaryEntryViewModel(context: PersistenceController.shared.container.viewContext))
}
