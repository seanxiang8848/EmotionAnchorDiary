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
                    VStack(spacing: 12) {
                        Text("暂无记录")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("写下一条心情，稍后可在这里查看")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries, id: \.objectID) { entry in
                        NavigationLink(destination: EntryDetailView(entry: entry)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.createdAt ?? Date(), style: .date)
                                    .font(.headline)
                                if let decrypted = decryptedText(for: entry) {
                                    Text(decrypted)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                } else {
                                    Text("解密失败或无内容")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteEntries)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史条目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
            VStack(alignment: .leading, spacing: 12) {
                if let date = entry.createdAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let moodTag = entry.moodTag, !moodTag.isEmpty {
                    Text("心情：\(moodTag)")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
                if let decrypted = decryptedText {
                    Text(decrypted)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("解密失败或无内容")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("日记全文")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 注意：deployment target 是 iOS 16，不能用 iOS 17 才有的 .destructiveAction placement
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
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
