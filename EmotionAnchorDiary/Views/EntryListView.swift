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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                StarTrailBackdrop()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(colorScheme == .dark ? 1 : 0.22)
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
                                        .fill(rowFill(for: entry))
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

    private func rowFill(for entry: Entry) -> Color {
        if colorScheme == .dark {
            return AppTheme.moodColor(entry.moodTag ?? "").opacity(0.08)
        }
        return AppTheme.surface
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
                            .font(.system(.caption))
                            .tracking(1.2)
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


/// 历史列表背景上的静态星点与细线，无交互、无动画；减弱动态效果时同样保持静止。
private struct StarTrailBackdrop: View {
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
        (0.08, 0.06, 1.6, 0.22), (0.22, 0.12, 1.1, 0.16), (0.41, 0.04, 1.3, 0.18),
        (0.63, 0.09, 1.0, 0.14), (0.81, 0.05, 1.7, 0.20), (0.93, 0.14, 1.2, 0.15),
        (0.14, 0.28, 1.0, 0.12), (0.33, 0.22, 1.5, 0.18), (0.52, 0.31, 1.1, 0.13),
        (0.71, 0.24, 1.8, 0.20), (0.88, 0.33, 1.2, 0.15), (0.06, 0.46, 1.3, 0.14),
        (0.27, 0.51, 1.0, 0.11), (0.48, 0.44, 1.6, 0.17), (0.69, 0.52, 1.1, 0.13),
        (0.86, 0.47, 1.4, 0.16), (0.17, 0.68, 1.2, 0.14), (0.39, 0.73, 1.5, 0.17),
        (0.58, 0.65, 1.0, 0.11), (0.77, 0.71, 1.7, 0.19), (0.94, 0.63, 1.1, 0.13),
        (0.11, 0.86, 1.3, 0.15), (0.31, 0.91, 1.0, 0.10), (0.55, 0.88, 1.4, 0.16),
        (0.74, 0.93, 1.1, 0.12), (0.90, 0.84, 1.6, 0.18)
    ]

    private let trails: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 0.10, y: 0.18), CGPoint(x: 0.38, y: 0.10), CGPoint(x: 0.72, y: 0.22)),
        (CGPoint(x: 0.18, y: 0.58), CGPoint(x: 0.50, y: 0.42), CGPoint(x: 0.88, y: 0.55)),
        (CGPoint(x: 0.08, y: 0.82), CGPoint(x: 0.42, y: 0.70), CGPoint(x: 0.80, y: 0.88))
    ]

    var body: some View {
        Canvas { context, size in
            let starColor = Color(red: 233/255, green: 228/255, blue: 218/255)
            let lineColor = Color(red: 232/255, green: 166/255, blue: 129/255)

            for trail in trails {
                var path = Path()
                path.move(to: CGPoint(x: trail.0.x * size.width, y: trail.0.y * size.height))
                path.addQuadCurve(
                    to: CGPoint(x: trail.2.x * size.width, y: trail.2.y * size.height),
                    control: CGPoint(x: trail.1.x * size.width, y: trail.1.y * size.height)
                )
                context.stroke(path, with: .color(lineColor.opacity(0.10)), lineWidth: 0.7)
            }

            for star in stars {
                let rect = CGRect(
                    x: star.x * size.width - star.r / 2,
                    y: star.y * size.height - star.r / 2,
                    width: star.r,
                    height: star.r
                )
                context.fill(Path(ellipseIn: rect), with: .color(starColor.opacity(star.a)))
            }
        }
    }
}

#Preview {
    EntryListView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
