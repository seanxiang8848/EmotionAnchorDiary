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
                    .frame(height: 200)
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
                         ? "开启后，仅将本地提取的前 3 句摘要（最多 300 字）发送到 AI 服务。"
                         : "关闭时，日记仅保存在本机，并使用本地共情文案。")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("录音中：\(Int(viewModel.recordingDuration))s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    ForEach(Array(viewModel.waveformSamples.enumerated()), id: \.offset) { _, sample in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.orange.opacity(0.7))
                                            .frame(width: 4, height: CGFloat(20 + sample * 40))
                                    }
                                }
                                .frame(height: 40)
                            }
                        }
                    }

                    Button(action: viewModel.handleSubmit) {
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

                if let empathyCard = viewModel.empathyCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(empathyCard.mood)
                            .font(.headline)
                        Text(empathyCard.empathy)
                        ForEach(empathyCard.suggestions, id: \.self) { suggestion in
                            Text("• \(suggestion)").font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }

                if !viewModel.goalSnapshots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("目标关联")
                            .font(.headline)
                        ForEach(viewModel.goalSnapshots) { snapshot in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(snapshot.title)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(snapshot.completedHits)/\(snapshot.targetFrequency)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                ProgressView(value: snapshot.progressValue)
                                    .progressViewStyle(.linear)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                }

                }
                .padding()
            }
            .navigationTitle("情绪锚点")
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

struct AppSettingsView: View {
    @ObservedObject var viewModel: DiaryEntryViewModel
    @Environment(\.managedObjectContext) private var context
    @State private var apiKey = AIKeyStore.load() ?? ""
    @State private var endpointText = APIConfig.load()?.endpoint.absoluteString ?? ""
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
                TextField("HTTPS 服务地址", text: $endpointText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("保存服务地址") {
                    if let config = APIConfig.validated(endpointText) {
                        UserDefaults.standard.set(config.endpoint.absoluteString, forKey: APIConfig.endpointDefaultsKey)
                        statusMessage = "HTTPS 服务地址已保存在本机。"
                    } else {
                        statusMessage = "请输入有效的 HTTPS 地址。"
                    }
                    showMessage = true
                }
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(APIConfig.load() == nil
                     ? "服务地址尚未配置。API Key 只保存在本机 Keychain。"
                     : "服务地址已配置。API Key 只保存在本机 Keychain。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("保存 API Key") {
                    do {
                        try AIKeyStore.save(apiKey)
                        statusMessage = "API Key 已安全保存到本机。"
                    } catch {
                        statusMessage = "保存失败，请检查设备 Keychain 状态。"
                    }
                    showMessage = true
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("删除本机 API Key", role: .destructive) {
                    do {
                        try AIKeyStore.delete()
                        apiKey = ""
                        statusMessage = "API Key 已删除。"
                    } catch {
                        statusMessage = "删除失败，请稍后重试。"
                    }
                    showMessage = true
                }
            }

            Section("隐私") {
                Toggle("启动时使用 Face ID 或设备密码", isOn: $requireAppUnlock)
                Text("AI 云端分析默认关闭。开启后，应用会先在本机提取日记摘要，再发送摘要；完整日记仍只保存在本机。")
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
            if case .failure = result {
                statusMessage = "导出失败，请检查存储位置后重试。"
                showMessage = true
            }
        }
        .confirmationDialog("删除全部日记和目标？此操作无法撤销。", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("删除全部数据", role: .destructive, action: deleteAllData)
            Button("取消", role: .cancel) { }
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
        do {
            for entry in try context.fetch(Entry.fetchRequest()) { context.delete(entry) }
            for goal in try context.fetch(Goal.fetchRequest()) { context.delete(goal) }
            try context.save()
        } catch {
            context.rollback()
            statusMessage = "删除本地数据失败，请重试。"
            showMessage = true
            return
        }

        allowCloudAnalysis = false
        viewModel.journalText = ""
        viewModel.empathyCard = nil
        viewModel.matchedGoals = []
        viewModel.goalSnapshots = []
        var keyCleanupFailed = false
        if !isUITesting {
            do { try CryptoManager.shared.deleteKey() } catch { keyCleanupFailed = true }
            do { try AIKeyStore.delete() } catch { keyCleanupFailed = true }
        }
        statusMessage = keyCleanupFailed
            ? "日记和目标已删除，但 Keychain 清理未能完整完成。"
            : "本机日记、目标和 AI 密钥已删除。"
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

private struct DiaryExportDocument: FileDocument {
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
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    DiaryEntryView(viewModel: DiaryEntryViewModel(context: PersistenceController.shared.container.viewContext))
}
