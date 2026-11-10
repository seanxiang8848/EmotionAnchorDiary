import Charts
import CoreData
import SwiftUI

struct MoodTrendView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Entry.createdAt, ascending: true)],
        animation: .easeInOut
    ) private var entries: FetchedResults<Entry>

    @State private var selectedRange = 7
    @Environment(\.colorScheme) private var colorScheme

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

    /// 当前所选时间窗口的 X 轴范围 [窗口首日, 明天]。
    /// 不显式设置的话，图表宽度只由已有数据决定：日记只有一两篇时，
    /// 切 7 天 / 30 天看起来“日期范围没变化”（其实只是没有旧数据）。
    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(selectedRange - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return start...end
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach([7, 30], id: \.self) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            Text("\(range) 天")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(rangeForeground(range))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(rangeBackground(range))
                                )
                                .overlay(
                                    Capsule().stroke(rangeStroke(range), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(Capsule().fill(colorScheme == .dark ? Color.clear : AppTheme.surfaceSoft))
                .overlay(
                    Capsule().stroke(colorScheme == .dark ? AppTheme.hairline : Color.clear, lineWidth: 1)
                )
                .frame(maxWidth: 260)

                if points.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.accent)
                            .padding(18)
                            .background(AppTheme.accentSoft)
                            .clipShape(Circle())
                        Text("还没有心情趋势")
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("保存日记并选择心情后，这里会按天显示平均心情。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionCaption(title: "心情曲线", symbol: "chart.xyaxis.line")
                        Chart(points) { point in
                            if colorScheme == .dark {
                                AreaMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppTheme.warm.opacity(0.28), AppTheme.warm.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 10, lineCap: .round))
                                .foregroundStyle(AppTheme.warm.opacity(0.22))

                                LineMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .foregroundStyle(AppTheme.warm)

                                PointMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .foregroundStyle(AppTheme.warm)
                            } else {
                                AreaMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(AppTheme.accent.opacity(0.16))

                                LineMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .foregroundStyle(AppTheme.accent)

                                PointMark(
                                    x: .value("日期", point.day),
                                    y: .value("心情", point.score)
                                )
                                .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .chartXScale(domain: xAxisDomain)
                        .chartYScale(domain: 1...5)
                        .chartYAxis {
                            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                                if colorScheme == .dark {
                                    AxisGridLine().foregroundStyle(AppTheme.hairline)
                                } else {
                                    AxisGridLine()
                                }
                                AxisValueLabel {
                                    if let score = value.as(Int.self), let mood = MoodOption.all.first(where: { Int($0.score) == score }) {
                                        Text(mood.tag)
                                    }
                                }
                            }
                        }
                        .frame(height: 260)
                    }
                    .paperCard()

                    Text("每天多条记录会取平均值。心情刻度由你主动选择，仅用于个人回顾。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .appScreenBackground()
        .navigationTitle("心情趋势")
    }

    private func rangeForeground(_ range: Int) -> Color {
        if colorScheme == .dark {
            return selectedRange == range ? AppTheme.warm : AppTheme.inkSoft
        }
        return selectedRange == range ? Color.white : AppTheme.inkSoft
    }

    private func rangeBackground(_ range: Int) -> Color {
        if colorScheme == .dark {
            return selectedRange == range ? AppTheme.warm.opacity(0.16) : Color.clear
        }
        return selectedRange == range ? AppTheme.accent : AppTheme.surface
    }

    private func rangeStroke(_ range: Int) -> Color {
        guard colorScheme == .dark else { return Color.clear }
        return selectedRange == range ? AppTheme.warm.opacity(0.35) : Color.clear
    }

}
