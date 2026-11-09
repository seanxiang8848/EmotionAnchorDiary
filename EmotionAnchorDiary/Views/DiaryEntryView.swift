import SwiftUI
import UIKit
import CoreData
import UniformTypeIdentifiers

struct DiaryEntryView: View {
    @ObservedObject var viewModel: DiaryEntryViewModel
    @State private var showSavedEntries: Bool = false
    /// 自定义 UITextView 自己管理第一响应者，用普通 State 同步焦点即可
    /// （FocusState 对 UIViewRepresentable 不生效，反而会让"完成"按钮收不起键盘）。
    @State private var isJournalFocused: Bool = false
    @AppStorage("allowCloudAnalysis") private var allowCloudAnalysis = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter
    }()

    private var todayCaption: String { Self.dayFormatter.string(from: Date()) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let banner = viewModel.feedbackBanner {
                        HStack(spacing: 10) {
                            Image(systemName: banner.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(banner.isError ? AppTheme.warm : AppTheme.accent)
                            Text(banner.message)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(banner.isError ? AppTheme.warmSoft : AppTheme.accentSoft)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(todayCaption)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        Text("今天的心情在哪儿？")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("写下来，就已经轻了一点。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.top, 4)

                    HStack(spacing: 10) {
                        Button {
                            showSavedEntries.toggle()
                        } label: {
                            QuickActionCard(title: "查看历史条目", symbol: "clock.arrow.circlepath", tint: AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看历史条目")
                        .frame(maxWidth: .infinity)

                        NavigationLink {
                            GoalDashboardView()
                                .environment(\.managedObjectContext, viewModel.viewContext)
                        } label: {
                            QuickActionCard(title: "目标追踪", symbol: "scope", tint: AppTheme.warm)
                        }
                        .accessibilityLabel("目标追踪")
                        .frame(maxWidth: .infinity)

                        NavigationLink {
                            MoodTrendView()
                                .environment(\.managedObjectContext, viewModel.viewContext)
                        } label: {
                            QuickActionCard(title: "心情趋势", symbol: "chart.xyaxis.line", tint: AppTheme.accent)
                        }
                        .accessibilityLabel("心情趋势")
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionCaption(title: "写下此刻", symbol: "square.and.pencil")
                        JournalTextView(text: $viewModel.journalText, isFocused: $isJournalFocused)
                            // 明确宽高：固定高度让 UITextView 自己滚动，避免与外层 ScrollView 抢手势。
                            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.hairline, lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if viewModel.journalText.isEmpty {
                                    Text("今天发生了什么？慢慢写，只有你能看到。")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionCaption(title: "此刻的心情", symbol: "heart.circle")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MoodOption.all) { mood in
                                    Button {
                                        viewModel.selectedMoodTag = mood.tag
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: AppTheme.moodSymbol(mood.tag))
                                                .font(.caption)
                                            Text(mood.tag)
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(
                                            Capsule().fill(
                                                viewModel.selectedMoodTag == mood.tag
                                                    ? AppTheme.moodColor(mood.tag)
                                                    : AppTheme.surfaceSoft
                                            )
                                        )
                                        .foregroundStyle(
                                            viewModel.selectedMoodTag == mood.tag
                                                ? Color.white
                                                : AppTheme.ink
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppTheme.accent)
                            Toggle("允许 AI 云端分析", isOn: $allowCloudAnalysis)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                                .tint(AppTheme.accent)
                        }
                        Text(allowCloudAnalysis
                             ? "开启后只发送本机提取的摘要（最多 3 句、300 字）与目标结构，不发送完整日记正文。"
                             : "关闭时，日记仅保存在本机，并使用本地共情文案。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        if allowCloudAnalysis && !viewModel.isAIReady {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "key.fill")
                                Text("还没有配置 API Key。点右上角齿轮 → AI 服务，选 DeepSeek 填 Key 就能接管情绪与目标分析。")
                            }
                            .font(.caption)
                            .foregroundStyle(AppTheme.warm)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .paperCard(padding: 14, radius: 18)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: viewModel.toggleRecording) {
                                Label(
                                    viewModel.isRecording ? "停止录音" : "语音记录",
                                    systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                                )
                            }
                            .buttonStyle(SoftSecondaryButtonStyle())
                            .accessibilityLabel(viewModel.isRecording ? "停止录音" : "语音记录")

                            if viewModel.isRecording {
                                // 计时与波形由子视图自持：每秒重渲染只发生在这个小组件里，
                                // 不会触发整页（含输入框）重算
                                RecordingIndicatorView()
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Button(action: {
                            isJournalFocused = false
                            viewModel.handleSubmit()
                        }) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "heart.fill")
                                    Text("保存并生成共情")
                                }
                            }
                        }
                        .buttonStyle(SoftPrimaryButtonStyle())
                        .accessibilityLabel("保存并生成共情")
                        .disabled(viewModel.isProcessing)
                        .frame(maxWidth: .infinity)
                    }

                    if viewModel.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("正在读取情绪与目标…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.surfaceSoft))
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
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appScreenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("情绪锚点")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.refreshAIStatus() }
            .toolbar {
                // 键盘上的「完成」由 JournalTextView 自带的 inputAccessoryView 提供：
                // SwiftUI 的 keyboard toolbar 对 UIViewRepresentable 不保证出现。
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AppSettingsView(viewModel: viewModel)) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(AppTheme.accent)
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

/// 首页三个快捷入口：图标 + 文字的小卡片，替代原先一排裸按钮。
private struct QuickActionCard: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13))
                .clipShape(Circle())
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - 日记正文输入框

/// 稳定的日记正文输入控件（替代 SwiftUI TextEditor）。
///
/// 背景：TextEditor 嵌套在 ScrollView 里时，输入过程中会出现已键入文字不绘制、
/// 光标前内容"消失"的渲染缺陷；深色模式下默认文字/背景对比也可能失效。
/// 上一轮把固定 height 改成 min/max 高度只是缓解，AI 版本页面内容变长后再次复现。
/// 这里直接用 UITextView：文字色 `.label`、背景 `.secondarySystemBackground`、
/// 光标 `.systemBlue` 都随深浅色外观自适应，滚动也由它自己管理。
///
/// 关键约束：updateUIView 只在外部文字真的变化时回写，否则整页重渲染
/// 会把光标位置和中文输入法的组合输入冲掉。
private struct JournalTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.accessibilityIdentifier = "diary-entry-editor"
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = AppTheme.inkUI
        // 背景交给 SwiftUI 层的纸感卡片，深浅色切换时自动跟着主题走。
        textView.backgroundColor = .clear
        textView.tintColor = AppTheme.accentUI
        textView.text = text
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.layer.cornerRadius = 18
        textView.clipsToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)

        // 自己提供键盘工具条：SwiftUI 的 .keyboard toolbar 挂在宿主视图上，
        // 对 UIViewRepresentable 内部的 firstResponder 不保证生效。
        let doneBar = UIToolbar()
        doneBar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                title: "完成",
                style: .done,
                target: context.coordinator,
                action: #selector(Coordinator.doneTapped)
            )
        ]
        doneBar.sizeToFit()
        textView.inputAccessoryView = doneBar
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // 不打断输入：键入时 binding 与 textView.text 相等，直接跳过回写。
        if (textView.text ?? "") != text {
            textView.text = text
        }
        // 提交按钮通过 isFocused 收起键盘；键盘工具条的「完成」直接 resign。
        if isFocused && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: JournalTextView
        weak var textView: UITextView?

        init(parent: JournalTextView) {
            self.parent = parent
        }

        @objc func doneTapped() {
            textView?.resignFirstResponder()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }
    }
}

/// 给仍然使用 SwiftUI 原生 TextField 的页面补键盘「完成」按钮。
/// 首页的键盘工具条由 JournalTextView 自带，这里只服务设置页 / 目标编辑页。
extension View {
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accentSoft)
                    .clipShape(Circle())
                Text("情绪解读")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 6)
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(analysis.emotion.label)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(emotionColor)
                    Text(intensityText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(analysis.emotion.score, specifier: "%.1f") / 5")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    ScoreBar(score: analysis.emotion.score, tint: emotionColor)
                }
            }

            Text(analysis.empathy)
                .font(.system(.body, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(emotionColor.opacity(0.65))
                        .frame(width: 3)
                }

            if !analysis.emotion.reason.isEmpty {
                Text("判断依据：\(analysis.emotion.reason)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !analysis.suggestions.isEmpty {
                Divider()
                Text("可以试试")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(analysis.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(emotionColor.opacity(0.65))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let note = note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warm)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(AppTheme.warmSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .paperCard()
    }

    private var emotionColor: Color {
        AppTheme.moodColor(analysis.emotion.label)
    }

    private var intensityText: String {
        switch analysis.emotion.intensity {
        case ..<0.35: return "强度：轻"
        case ..<0.7: return "强度：中"
        default: return "强度：强"
        }
    }
}

/// 五格心情分值条，比一串数字更容易一眼读懂。
private struct ScoreBar: View {
    let score: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Capsule()
                    .fill(Double(index) <= score.rounded() ? tint : AppTheme.surfaceSoft)
                    .frame(width: 16, height: 5)
            }
        }
    }
}

// MARK: - 目标动向卡

private struct GoalInsightCard: View {
    let snapshots: [DiaryEntryViewModel.GoalProgressSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.warm)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.warmSoft)
                    .clipShape(Circle())
                Text("目标动向")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            ForEach(snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(snapshot.completedDays)/\(snapshot.targetDays) 天")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    ProgressView(value: snapshot.progressValue)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.accent)
                    if let note = snapshot.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(note)
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(AppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .paperCard()
    }
}

/// 录音中的计时 + 波形指示。
///
/// 每秒刷新只发生在这个子视图内部（自持 Timer 与状态），
/// 不会通过 ViewModel 的 @Published 触发整页重渲染——
/// 否则手动输入日记时每秒钟页面重算会让输入框的光标/内容显示异常。
private struct RecordingIndicatorView: View {
    @State private var elapsedSeconds: Int = 0
    @State private var samples: [Double] = Array(repeating: 0.3, count: 12)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(AppTheme.warm).frame(width: 7, height: 7)
                Text("录音中：\(elapsedSeconds)s")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warm)
            }
            HStack(spacing: 4) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(AppTheme.warm.opacity(0.75))
                        .frame(width: 4, height: CGFloat(10 + sample * 26))
                }
            }
            .frame(height: 36)
        }
        .padding(10)
        .background(AppTheme.warmSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onReceive(timer) { _ in
            elapsedSeconds += 1
            samples = (0..<12).map { _ in Double.random(in: 0.2...0.9) }
        }
    }
}

// MARK: - 设置

private struct SettingsSectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(AppTheme.inkSoft)
    }
}

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
            Section {
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
                    .foregroundStyle(AppTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("API 地址（https）", text: $baseURLText)
                    .foregroundStyle(AppTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API Key", text: $apiKey)
                    .foregroundStyle(AppTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveAndTestConnection()
                } label: {
                    HStack(spacing: 8) {
                        if isTestingConnection {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(isTestingConnection ? "正在测试连接…" : "保存并测试连接")
                            .fontWeight(.medium)
                    }
                }
                .disabled(isTestingConnection)
                .foregroundStyle(AppTheme.accent)

                Toggle("保存日记时使用 AI 分析", isOn: $allowCloudAnalysis)
                    .tint(AppTheme.accent)

                if let status = aiStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(aiStatusIsError ? AppTheme.warm : AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(aiStatusIsError ? AppTheme.warmSoft : AppTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("密钥只保存在本机钥匙串。\(provider.keyHint)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)

                Button("删除本机 API Key", role: .destructive) {
                    deleteAPIKey()
                }
            } header: {
                SettingsSectionHeader(title: "AI 服务", symbol: "sparkles")
            }
            .listRowBackground(AppTheme.surface)
            .listRowSeparatorTint(AppTheme.hairline)

            Section {
                Toggle("启动时使用 Face ID 或设备密码", isOn: $requireAppUnlock)
                    .accessibilityIdentifier("app-lock-toggle")
                    .tint(AppTheme.accent)
                Text("AI 云端分析默认关闭。开启后，应用会先在本机提取摘要（最多 3 句、300 字）再发送，完整日记仍只保存在本机；关闭或失败时使用本地共情文案。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.inkSoft)
                Button("导出日记") {
                    prepareExport()
                }
                .foregroundStyle(AppTheme.accent)
                Button("删除所有本地日记和目标…", role: .destructive) {
                    confirmDeleteAll = true
                }
            } header: {
                SettingsSectionHeader(title: "隐私", symbol: "lock.shield")
            }
            .listRowBackground(AppTheme.surface)
            .listRowSeparatorTint(AppTheme.hairline)
        }
        .scrollContentBackground(.hidden)
        .appScreenBackground()
        .keyboardDoneToolbar()
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
