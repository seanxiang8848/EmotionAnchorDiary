import SwiftUI
import CoreData

struct EntryListView: View {
    @Environment(\.dismiss) private var dismiss

    // Uses the managedObjectContext injected via .environment from the presenting view
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: false)],
        animation: .easeInOut
    ) private var entries: FetchedResults<Entry>

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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.createdAt ?? Date(), style: .date)
                                .font(.headline)
                            if let encrypted = entry.encryptedBody, let decrypted = try? CryptoManager.shared.decrypt(encrypted) {
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
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史条目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    EntryListView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
