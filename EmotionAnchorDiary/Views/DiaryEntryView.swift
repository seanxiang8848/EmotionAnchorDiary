import SwiftUI
import UIKit
import CoreData
import UniformTypeIdentifiers

/// 主导航：书写、目标、时间轴三个一级页面。
struct DiaryHomeTabs: View {
    @ObservedObject var viewModel: DiaryEntryViewModel

    var body: some View {
        TabView {
            DiaryEntryView(viewModel: viewModel)
                .tabItem { Label("写日记", systemImage: "square.and.pencil") }
            NavigationStack {
                GoalDashboardView()
            }
            .tabItem { Label("目标", systemImage: "scope") }
            NavigationStack {
                EntryListView()
            }
            .tabItem { Label("时间轴", systemImage: "clock") }
        }
        .tint(AppTheme.warm)
    }
}

struct DiaryEntryView: View {
    @ObservedObject var viewModel: DiaryEntryViewModel
    /// 自定义 UITextView 自己管理第一响应者，用普通 State 同步焦点即可
    /// （FocusState 对 UIViewRepresentable 不生效，反而会让"完成"按钮收不起键盘）。
    @State private var isJournalFocused: Bool = false
    @Environment(\.colorScheme) private var colorScheme

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
                VStack(alignment: .leading, spacing: 24) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text(todayCaption)
                            .font(.system(.caption))
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.inkSoft)
                        Text("今天的心情在哪儿？")
                            .font(.system(size: 28, weight: .light, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                        Text("写下来，就已经轻了一点。")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionCaption(title: "写下此刻", symbol: "square.and.pencil")
                        // 卡片背景、描边、占位提示都放在容器上，不再给 UIViewRepresentable
                        // 叠 .background/.overlay：宿主视图被合成进 SwiftUI 图层时，
                        // 真机上更容易触发 UIKit 文字层不绘制。
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(colorScheme == .dark ? AppTheme.canvas : AppTheme.surface)
                            JournalTextView(text: $viewModel.journalText, isFocused: $isJournalFocused)
                                // 明确宽高：固定高度让 UITextView 自己滚动，避免与外层 ScrollView 抢手势。
                                // 快捷入口挪走后腾出空间，输入框加高到 300。
                                .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300)
                            if viewModel.journalText.isEmpty {
                                Text("今天发生了什么？慢慢写，只有你能看到。")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.inkSoft)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionCaption(title: "此刻的心情", symbol: "heart.circle")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MoodOption.all) { mood in
                                    Button {
                                        viewModel.selectedMoodTag = mood.tag
                                    } label: {
                                        MoodCapsuleLabel(
                                            tag: mood.tag,
                                            isSelected: viewModel.selectedMoodTag == mood.tag
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

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
                                    .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? AppTheme.warm : .white))
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "heart.fill")
                                    Text("保存")
                                }
                            }
                        }
                        .buttonStyle(SoftPrimaryButtonStyle())
                        .accessibilityLabel("保存")
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
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
    }
}

/// 五档心情胶囊：浅色保持实心色块；深色为透明底 + 低对比描边，选中态用该心情色的暖光描边。
private struct MoodCapsuleLabel: View {
    let tag: String
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: AppTheme.moodSymbol(tag))
                .font(.caption)
            Text(tag)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(capsuleBackground)
        .overlay(
            Capsule().stroke(capsuleStrokeColor, lineWidth: 1)
        )
        .foregroundStyle(capsuleForeground)
        .shadow(
            color: colorScheme == .dark && isSelected ? AppTheme.moodColor(tag).opacity(0.35) : Color.clear,
            radius: 6,
            x: 0,
            y: 0
        )
    }

    private var capsuleBackground: some View {
        Group {
            if colorScheme == .dark {
                Capsule().fill(Color.clear)
            } else {
                Capsule().fill(isSelected ? AppTheme.moodColor(tag) : AppTheme.surfaceSoft)
            }
        }
    }

    private var capsuleStrokeColor: Color {
        guard colorScheme == .dark else { return Color.clear }
        return isSelected ? AppTheme.moodColor(tag).opacity(0.85) : AppTheme.hairline
    }

    private var capsuleForeground: Color {
        if colorScheme == .dark {
            return isSelected ? AppTheme.moodColor(tag) : AppTheme.ink
        }
        return isSelected ? Color.white : AppTheme.ink
    }
}

// MARK: - 日记正文输入框

/// 稳定的日记正文输入控件。
///
/// 真机复现记录（第三轮）：中文输入法 + 深色模式下，文字已写进 binding、
/// 光标也随字数前进，但字形一个像素都不绘制（截图放大 4 倍、提亮 4 倍后仍是纯色）。
/// 所以这既不是数据被清空，也不是「深色字写在深色底」的对比度问题，
/// 而是 UIKit 文字层的字形生成 / 合成失败。SwiftUI `TextEditor` 与 iOS 17+
/// 默认的 `UITextView` 都跑在 **TextKit 2** 上，正是这类缺陷的高发路径，
/// 也解释了为什么模拟器全绿、真机连续两轮复现。
///
/// 本实现同时切断四条已知触发路径：
/// 1. 用显式 NSTextStorage / NSLayoutManager 构造 UITextView，强制 **TextKit 1**；
/// 2. 文字色、光标色按当前外观解析成静态不透明 UIColor，动态色不进 textStorage；
/// 3. 编辑期间绝不写 textView.text（含中文组合输入 markedTextRange），
///    只有录音转写、保存后清空这类「外部写值」才回写；
/// 4. 去掉 UITextView 自己的 layer.cornerRadius，圆角由 SwiftUI 卡片负责。
private struct JournalTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        // 手工搭一套 TextKit 1 栈：iOS 16+ 传入自定义 textContainer 即走 TextKit 1，
        // 不会创建 TextKit 2 那层独立的文字画布（真机上偶发整层不合成）。
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.accessibilityIdentifier = "diary-entry-editor"
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        // 背景交给 SwiftUI 的纸感卡片；这里只保留 UIScrollView 默认裁切，
        // 不再给 layer 设圆角，避免文字层被 mask 掉。
        textView.backgroundColor = .clear
        textView.clipsToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)

        context.coordinator.textView = textView
        context.coordinator.lastTextFromEditor = text
        context.coordinator.applyEditorStyleIfNeeded(force: true)
        context.coordinator.replaceText(with: text)

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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyEditorStyleIfNeeded()

        // 用户键入时 lastTextFromEditor 与 text 相等，绝不触碰 textStorage。
        // 只有外部写值（语音转写 / 保存后清空）才会走到这里。
        if text != coordinator.lastTextFromEditor {
            // 中文输入法组合输入期间延后回写，下一轮 SwiftUI 更新会补上。
            guard textView.markedTextRange == nil else { return }
            coordinator.replaceText(with: text)
            coordinator.lastTextFromEditor = text
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
        /// 编辑器自己上报的最后一份文字，用来区分「用户键入」与「外部写值」。
        var lastTextFromEditor: String = ""
        private var appliedStyle: UIUserInterfaceStyle = .unspecified

        init(parent: JournalTextView) {
            self.parent = parent
        }

        @objc func doneTapped() {
            textView?.resignFirstResponder()
        }

        /// 动态 UIColor 放进 textStorage / typingAttributes 时，
        /// iOS 17+ 有概率按错误的外观解析，导致字形以透明色绘制。
        /// 这里统一按当前外观解析成静态色，外观切换时再刷一遍。
        func applyEditorStyleIfNeeded(force: Bool = false) {
            let style = AppTheme.currentInterfaceStyle
            guard force || style != appliedStyle else { return }
            appliedStyle = style
            guard let textView = textView else { return }

            let ink = AppTheme.editorInk(for: style)
            let attributes = Self.textAttributes(font: textView.font, ink: ink)
            textView.textColor = ink
            textView.tintColor = AppTheme.editorTint(for: style)
            textView.typingAttributes = attributes

            let length = (textView.text ?? "").utf16.count
            if length > 0 {
                textView.textStorage.addAttribute(
                    .foregroundColor,
                    value: ink,
                    range: NSRange(location: 0, length: length)
                )
            }
            forceGlyphRedraw(in: textView, length: length)
        }

        /// 外部写值：整段带显式字体与前景色重建，并强制重新生成字形。
        func replaceText(with value: String) {
            guard let textView = textView else { return }
            let attributes = Self.textAttributes(
                font: textView.font,
                ink: AppTheme.editorInk(for: AppTheme.currentInterfaceStyle)
            )
            textView.attributedText = NSAttributedString(string: value, attributes: attributes)
            textView.typingAttributes = attributes
            textView.selectedRange = NSRange(location: value.utf16.count, length: 0)
            forceGlyphRedraw(in: textView, length: value.utf16.count)
        }

        private func forceGlyphRedraw(in textView: UITextView, length: Int) {
            if length > 0 {
                textView.layoutManager.invalidateDisplay(
                    forCharacterRange: NSRange(location: 0, length: length)
                )
            }
            textView.setNeedsDisplay()
        }

        private static func textAttributes(
            font: UIFont?,
            ink: UIColor
        ) -> [NSAttributedString.Key: Any] {
            [
                .font: font ?? UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: ink
            ]
        }

        func textViewDidChange(_ textView: UITextView) {
            let value = textView.text ?? ""
            lastTextFromEditor = value
            parent.text = value

            // 保险：下一个 runloop 强制重算字形。真机上曾出现 textStorage 有文字、
            // 布局知道宽度（光标前进）、但字形缓存没刷新的情况；这里只重绘，
            // 不改 textStorage，不会打断中文输入法的组合输入。
            weak var weakTextView = textView
            DispatchQueue.main.async {
                guard let current = weakTextView else { return }
                let length = (current.text ?? "").utf16.count
                if length > 0 {
                    current.layoutManager.invalidateDisplay(
                        forCharacterRange: NSRange(location: 0, length: length)
                    )
                }
                current.setNeedsDisplay()
            }
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
    @State private var haloScale: CGFloat = 1
    @State private var reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    if !reduceMotionEnabled {
                        Circle()
                            .stroke(AppTheme.warm.opacity(0.45), lineWidth: 1)
                            .frame(width: 16, height: 16)
                            .scaleEffect(haloScale)
                            .opacity(2.1 - Double(haloScale))
                    }
                    Circle().fill(AppTheme.warm).frame(width: 7, height: 7)
                }
                .frame(width: 18, height: 18)
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
        .onAppear { syncHaloAnimation() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
            syncHaloAnimation()
        }
        .onReceive(timer) { _ in
            elapsedSeconds += 1
            if !reduceMotionEnabled {
                samples = (0..<12).map { _ in Double.random(in: 0.2...0.9) }
            }
        }
    }

    private func syncHaloAnimation() {
        if reduceMotionEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                haloScale = 1
            }
        } else {
            haloScale = 1
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                haloScale = 1.8
            }
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

                Toggle("允许 AI 云端分析", isOn: $allowCloudAnalysis)
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
