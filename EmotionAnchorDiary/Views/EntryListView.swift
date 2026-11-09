import SwiftUI
import CoreData

struct EntryListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // Uses the managedObjectContext injected via .environment from the presenting view
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: false)],
        animation: .easeInOut
    ) private var entries: FetchedResults<Entry>

    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.accent)
                            .padding(18)
                            .background(AppTheme.accentSoft)
                            .clipShape(Circle())
                        Text("暂无记录")
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("写下一条心情，稍后可在这里查看")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(entries, id: \.objectID) { entry in
                            NavigationLink(destination: EntryDetailView(entry: entry)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(AppTheme.moodColor(entry.moodTag ?? ""))
                                            .frame(width: 8, height: 8)
                                        Text(entry.createdAt ?? Date(), style: .date)
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(AppTheme.inkSoft)
                                        Spacer()
                                        if let moodTag = entry.moodTag, !moodTag.isEmpty {
                                            Text(moodTag)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.moodColor(moodTag))
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(
                                                    Capsule().fill(AppTheme.moodColor(moodTag).opacity(0.14))
                                                )
                                        }
                                    }
                                    if let decrypted = decryptedText(for: entry) {
                                        Text(decrypted)
                                            .font(.system(.body, design: .serif))
                                            .foregroundStyle(AppTheme.ink)
                                            .lineLimit(3)
                                    } else {
                                        Text("解密失败或无内容")
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.inkSoft)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.hairline, lineWidth: 1)
                                )
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .appScreenBackground()
            .navigationTitle("历史条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .alert("删除失败", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func decryptedText(for entry: Entry) -> String? {
        guard let encrypted = entry.encryptedBody else { return nil }
        return try? CryptoManager.shared.decrypt(encrypted)
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { entries[$0] }.forEach(viewContext.delete)
        do {
            try viewContext.save()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

/// 单篇日记的全文视图：点开任意一条历史条目可通读全文，也可从这里删除该条。
private struct EntryDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let entry: Entry

    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if let date = entry.createdAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    if let moodTag = entry.moodTag, !moodTag.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: AppTheme.moodSymbol(moodTag))
                            Text("心情：\(moodTag)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.moodColor(moodTag))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(AppTheme.moodColor(moodTag).opacity(0.14))
                        )
                    }
                    if let decrypted = decryptedText {
                        Text(decrypted)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("解密失败或无内容")
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .paperCard()

                if let analysis = entry.aiAnalysis {
                    AnalysisCardView(analysis: analysis, badge: "保存时分析", note: nil)
                }

                if let goals = entry.goals as? Set<Goal>, !goals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionCaption(title: "关联目标", symbol: "link")
                        ForEach(Array(goals).sorted { ($0.title ?? "") < ($1.title ?? "") }, id: \.objectID) { goal in
                            HStack(spacing: 8) {
                                Circle().fill(AppTheme.accent).frame(width: 5, height: 5)
                                Text(goal.title ?? "未命名目标")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                    .paperCard()
                }
            }
            .padding(18)
        }
        .appScreenBackground()
        .navigationTitle("日记全文")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 注意：deployment target 是 iOS 16，不能用 iOS 17 才有的 .destructiveAction placement
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.warm)
                }
                .accessibilityLabel("删除这篇日记")
            }
        }
        .confirmationDialog("删除这篇日记？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: deleteEntry)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不可恢复。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private var decryptedText: String? {
        guard let encrypted = entry.encryptedBody else { return nil }
        return try? CryptoManager.shared.decrypt(encrypted)
    }

    private func deleteEntry() {
        viewContext.delete(entry)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    EntryListView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
