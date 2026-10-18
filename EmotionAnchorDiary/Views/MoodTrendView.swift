import Charts
import CoreData
import SwiftUI

struct MoodTrendView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: true)],
        animation: .easeInOut
    ) private var entries: FetchedResults<Entry>

    @State private var selectedRange = 7

    private struct MoodPoint: Identifiable {
        let day: Date
        let score: Double
        var id: Date { day }
    }

    private var points: [MoodPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -(selectedRange - 1), to: today) else { return [] }

        let grouped = Dictionary(grouping: entries.compactMap { entry -> (Date, Double)? in
            guard let date = entry.createdAt,
                  let mood = MoodOption.all.first(where: { $0.tag == entry.moodTag }),
                  date >= firstDay,
                  date < (calendar.date(byAdding: .day, value: 1, to: today) ?? today) else { return nil }
            return (calendar.startOfDay(for: date), mood.score)
        }, by: { $0.0 })

        return grouped.map { day, values in
            MoodPoint(day: day, score: values.map { $0.1 }.reduce(0, +) / Double(values.count))
        }.sorted { $0.day < $1.day }
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("时间范围", selection: $selectedRange) {
                Text("7 天").tag(7)
                Text("30 天").tag(30)
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundColor(.secondary)
                    Text("还没有心情趋势")
                        .font(.headline)
                    Text("保存日记并选择心情后，这里会按天显示平均心情。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("日期", point.day),
                        y: .value("心情", point.score)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.orange)

                    PointMark(
                        x: .value("日期", point.day),
                        y: .value("心情", point.score)
                    )
                    .foregroundStyle(Color.orange)
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let score = value.as(Int.self), let mood = MoodOption.all.first(where: { Int($0.score) == score }) {
                                Text(mood.tag)
                            }
                        }
                    }
                }
                .frame(height: 280)

                Text("每天多条记录会取平均值。心情刻度由你主动选择，仅用于个人回顾。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("心情趋势")
    }
}
