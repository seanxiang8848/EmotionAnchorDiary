import CoreData
import SwiftUI

struct GoalDashboardView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Goal.lastUpdatedAt, ascending: false)],
        animation: .easeInOut
    ) private var goals: FetchedResults<Goal>

    @State private var showingEditor = false
    @State private var editingGoal: Goal?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if goals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "scope")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.accent)
                        .padding(18)
                        .background(AppTheme.accentSoft)
                        .clipShape(Circle())
                    Text("还没有目标")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("添加一个小目标，日记中提到关键词时会自动记录进度。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(goals, id: \.objectID) { goal in
                Button {
                    editingGoal = goal
                    showingEditor = true
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title ?? "未命名目标")
                                    .font(.system(.headline, design: .serif, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(goal.goalRuleText)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            Spacer(minLength: 8)
                            Text("\(goal.completedDays())/\(goal.effectiveTargetDays)")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        ProgressView(value: goal.progressValue)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accent)
                        if !goal.keywordList.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(goal.keywordList.prefix(3)), id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(AppTheme.surfaceSoft))
                                }
                                if goal.keywordList.count > 3 {
                                    Text("+\(goal.keywordList.count - 3)")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions {
                    Button(role: .destructive) {
                        do {
                            try GoalManager(context: context).deleteGoal(goal)
                        } catch {
                            errorMessage = "删除失败，请稍后重试。"
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appScreenBackground()
        .navigationTitle("目标追踪")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingGoal = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityLabel("添加目标")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingGoal = nil }) {
            NavigationView {
                GoalEditorView(goal: editingGoal)
                    .environment(\.managedObjectContext, context)
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct GoalEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let goal: Goal?
    @State private var title: String
    @State private var keywordsText: String
    @State private var targetFrequency: Int
    @State private var periodDays: Int
    @State private var errorMessage: String?

    init(goal: Goal?) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _keywordsText = State(initialValue: (goal?.keywordList ?? []).joined(separator: ", "))
        let period = max(1, Int(goal?.periodDays ?? 7))
        _periodDays = State(initialValue: period)
        // 目标天数不能超过周期天数
        _targetFrequency = State(initialValue: min(max(1, Int(goal?.targetFrequency ?? 1)), period))
    }

    var body: some View {
        Form {
            Section {
                TextField("例如：每天散步", text: $title)
                    .foregroundStyle(AppTheme.ink)
                    .textInputAutocapitalization(.none)
                TextField("关键词，用逗号分隔", text: $keywordsText)
                    .foregroundStyle(AppTheme.ink)
                    .textInputAutocapitalization(.never)
            } header: {
                SectionCaption(title: "目标内容", symbol: "pencil")
            }
            .listRowBackground(AppTheme.surface)
            .listRowSeparatorTint(AppTheme.hairline)

            Section {
                Stepper("周期：最近 \(periodDays) 天", value: $periodDays, in: 1...30)
                Stepper("周期内完成：\(targetFrequency) 天", value: $targetFrequency, in: 1...max(1, periodDays))
                Text("日记正文包含任一关键词时算作当天完成。同一天写多篇只算一天，超出周期的记录不再计入。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
            } header: {
                SectionCaption(title: "进度目标", symbol: "chart.bar")
            }
            .onChange(of: periodDays) { newValue in
                if targetFrequency > newValue { targetFrequency = newValue }
            }
            .listRowBackground(AppTheme.surface)
            .listRowSeparatorTint(AppTheme.hairline)
        }
        .scrollContentBackground(.hidden)
        .appScreenBackground()
        .keyboardDoneToolbar()
        .navigationTitle(goal == nil ? "新建目标" : "编辑目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        // 支持中英文逗号、顿号、分号、空格分隔关键词
        let separators = CharacterSet(charactersIn: ",，、;； 　")
        let keywords = keywordsText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // 目标天数不能超过周期天数
        let target = max(1, min(targetFrequency, periodDays))
        do {
            let manager = GoalManager(context: context)
            if let goal {
                try manager.updateGoal(
                    goal,
                    title: title,
                    keywords: keywords,
                    targetFrequency: Int16(target),
                    periodDays: Int16(periodDays)
                )
            } else {
                _ = try manager.createGoal(
                    title: title,
                    keywords: keywords,
                    targetFrequency: Int16(target),
                    periodDays: Int16(periodDays)
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
