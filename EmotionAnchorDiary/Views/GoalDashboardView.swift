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
                            Text("\(goal.hits)/\(max(1, Int(goal.targetFrequency)))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: min(1, Double(goal.hits) / Double(max(1, Int(goal.targetFrequency)))))
                        Text("关键词：\((goal.keywords ?? []).joined(separator: "、"))")
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
    @State private var errorMessage: String?

    init(goal: Goal?) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _keywordsText = State(initialValue: (goal?.keywords ?? []).joined(separator: ", "))
        _targetFrequency = State(initialValue: max(1, Int(goal?.targetFrequency ?? 1)))
    }

    var body: some View {
        Form {
            Section("目标内容") {
                TextField("例如：每天散步", text: $title)
                TextField("关键词，用逗号分隔", text: $keywordsText)
                    .textInputAutocapitalization(.never)
            }
            Section("进度目标") {
                Stepper("累计目标：\(targetFrequency) 次", value: $targetFrequency, in: 1...100)
                Text("日记正文包含任一关键词时，进度增加一次。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(goal == nil ? "新建目標" : "编辑目标")
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
        let keywords = keywordsText.components(separatedBy: ",")
        do {
            let manager = GoalManager(context: context)
            if let goal {
                try manager.updateGoal(goal, title: title, keywords: keywords, targetFrequency: Int16(targetFrequency))
            } else {
                _ = try manager.createGoal(title: title, keywords: keywords, targetFrequency: Int16(targetFrequency))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
