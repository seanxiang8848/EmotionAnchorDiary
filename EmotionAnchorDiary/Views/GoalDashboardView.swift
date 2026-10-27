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
                VStack(spacing: 8) {
                    Image(systemName: "scope").font(.largeTitle).foregroundColor(.secondary)
                    Text("还没有目标").font(.headline)
                    Text("添加一个小目标，日记中提到关键词时会自动记录进度。")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            }

            ForEach(goals, id: \.objectID) { goal in
                Button {
                    editingGoal = goal
                    showingEditor = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.title ?? "未命名目标")
                                .font(.headline)
                            Spacer()
                            Text("\(goal.completedDays())/\(goal.effectiveTargetDays) 天")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: goal.progressValue)
                        Text(goal.goalRuleText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("关键词：\(goal.keywordList.joined(separator: "、"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .navigationTitle("目标追踪")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingGoal = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
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
            Section("目标内容") {
                TextField("例如：每天散步", text: $title)
                    .textInputAutocapitalization(.none)
                TextField("关键词，用逗号分隔", text: $keywordsText)
                    .textInputAutocapitalization(.never)
            }
            Section("进度目标") {
                Stepper("周期：最近 \(periodDays) 天", value: $periodDays, in: 1...30)
                Stepper("周期内完成：\(targetFrequency) 天", value: $targetFrequency, in: 1...max(1, periodDays))
                Text("日记正文包含任一关键词时算作当天完成。同一天写多篇只算一天，超出周期的记录不再计入。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onChange(of: periodDays) { newValue in
                if targetFrequency > newValue { targetFrequency = newValue }
            }
        }
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
