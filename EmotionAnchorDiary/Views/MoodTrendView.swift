import Charts
import CoreData
import SwiftUI

struct MoodTrendView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: true)],
        animation: .easeInOut
    ) private var entries: FetchedResults<Entry>

    @State private var selectedRange = 7

    /// 计算逻辑放在 MoodTrendCalculator 里，便于单元测试覆盖日期边界。
    private var points: [MoodTrendCalculator.MoodPoint] {
        let samples = entries.compactMap { entry -> MoodTrendCalculator.MoodSample? in
            guard let date = entry.createdAt, let mood = moodOption(for: entry.moodTag) else { return nil }
            return MoodTrendCalculator.MoodSample(date: date, score: mood.score)
        }
        return MoodTrendCalculator.dailyAveragePoints(from: samples, rangeDays: selectedRange)
    }

    private func moodOption(for tag: String?) -> MoodOption? {
        MoodOption.all.first { $0.tag == tag }
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
