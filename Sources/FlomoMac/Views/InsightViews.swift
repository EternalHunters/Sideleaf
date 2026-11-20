import SwiftUI
import SwiftData

struct InsightBrowserView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]

    private var snapshot: InsightSnapshot {
        InsightEngine.make(range: app.insightRange, memos: memos)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("回望")
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.ink)
                Text("把一段时间摊开来看")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.hairlineSoft).frame(height: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 5) {
                        ForEach(InsightRange.allCases) { range in
                            rangeRow(range)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("这段时间")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                            .tracking(0.7)

                        HStack(spacing: 0) {
                            metric(value: "\(snapshot.count)", label: "记录")
                            divider
                            metric(value: "\(snapshot.activeDays)", label: "活跃天")
                            divider
                            metric(value: String(format: "%.1f", snapshot.averagePerActiveDay), label: "条/天")
                        }
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Theme.card.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Theme.hairlineSoft, lineWidth: 0.7)
                        )
                    }

                    if !snapshot.tagCounts.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("最近的主题")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                                .tracking(0.7)

                            ForEach(Array(snapshot.tagCounts.prefix(4).enumerated()), id: \.offset) { index, item in
                                Button {
                                    app.select(.tag(item.0))
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(Theme.inkGhost)
                                        Text("#" + item.0)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.tag)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(item.1)")
                                            .font(.system(size: 10, design: .rounded))
                                            .foregroundStyle(Theme.inkFaint)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 1)
                        Text("所有统计都在这台 Mac 上完成，不调用模型，也不上传正文。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkFaint)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .background(Theme.accentMist.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Theme.bg)
    }

    private func rangeRow(_ range: InsightRange) -> some View {
        let selected = app.insightRange == range
        let count = InsightEngine.make(range: range, memos: memos).count
        return Button { app.insightRange = range } label: {
            HStack(spacing: 9) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.accent : Theme.inkGhost)
                Text(range.title)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(selected ? Theme.accent.opacity(0.8) : Theme.inkFaint)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.accentSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairlineSoft).frame(width: 0.7, height: 25)
    }
}

struct InsightDetailView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]

    private var snapshot: InsightSnapshot {
        InsightEngine.make(range: app.insightRange, memos: memos)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.bottom, 26)

                AIReviewSection(memos: memos)
                    .padding(.bottom, 26)

                statsGrid
                    .padding(.bottom, 22)

                rhythmSection
                    .padding(.bottom, 26)

                if !snapshot.tagCounts.isEmpty {
                    tagSection
                        .padding(.bottom, 26)
                }

                observationSection
                    .padding(.bottom, 26)

                if !snapshot.highlights.isEmpty {
                    highlightSection
                        .padding(.bottom, 20)
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("本机统计基于笔记的日期、标签和字数。")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.inkGhost)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 54)
            .padding(.top, 40)
            .padding(.bottom, 66)
        }
        .background(PaperBackdrop())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("LOOKING BACK")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .tracking(2.2)
                Rectangle().fill(Theme.accent.opacity(0.25)).frame(width: 34, height: 1)
            }

            Text(heroTitle)
                .font(.system(size: 31, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Text(snapshot.periodLabel)
                Text("·")
                    .foregroundStyle(Theme.inkGhost)
                Text("\(snapshot.count) 条记录")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.inkSoft)
        }
    }

    private var heroTitle: String {
        if snapshot.count == 0 { return "这段时间，纸上很安静" }
        switch app.insightRange {
        case .week: return "这一周，你在想什么"
        case .month: return "这三十天留下的线索"
        case .all: return "把走过的路摊开"
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCard(value: "\(snapshot.count)", label: "条记录", hint: "words of you")
            statCard(value: "\(snapshot.activeDays)", label: "个活跃日", hint: activeHint)
            statCard(value: "\(snapshot.tagCounts.count)", label: "个标签", hint: "threads")
            statCard(value: compactCharacters, label: "字", hint: "written")
        }
    }

    private var activeHint: String {
        guard snapshot.count > 0 else { return "blank" }
        return String(format: "%.1f 条/天", snapshot.averagePerActiveDay)
    }

    private var compactCharacters: String {
        if snapshot.totalCharacters >= 10_000 {
            return String(format: "%.1f万", Double(snapshot.totalCharacters) / 10_000)
        }
        return "\(snapshot.totalCharacters)"
    }

    private func statCard(value: String, label: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkSoft)
            Text(hint)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(Theme.inkGhost)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.card.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 0.7)
        )
    }

    // MARK: 节奏

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("写作的节奏", note: app.insightRange == .all ? "最近 13 周" : snapshot.periodLabel)

            if app.insightRange == .all {
                ContributionGrid(counts: snapshot.dayCounts, weeks: 13)
                    .padding(.top, 2)
            } else {
                RhythmBars(series: snapshot.series, range: app.insightRange)
                    .frame(height: 110)
            }

            HStack(spacing: 12) {
                if let busiest = snapshot.busiestWeekday, snapshot.count > 0 {
                    Label("\(busiest)最常动笔", systemImage: "pencil.line")
                }
                if snapshot.activeDays > 0 {
                    Label("平均每天 \(String(format: "%.1f", snapshot.averagePerActiveDay)) 条", systemImage: "chart.bar")
                }
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: 标签

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("反复出现的线索", note: "\(snapshot.tagCounts.count) 个标签")

            VStack(spacing: 9) {
                ForEach(Array(snapshot.tagCounts.prefix(6).enumerated()), id: \.offset) { _, item in
                    let maxCount = max(snapshot.tagCounts.first?.1 ?? 1, 1)
                    Button {
                        app.select(.tag(item.0))
                    } label: {
                        HStack(spacing: 10) {
                            Text("#" + item.0)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.tag)
                                .frame(width: 150, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.field.opacity(0.6))
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.55))
                                        .frame(width: max(6, geo.size.width * CGFloat(item.1) / CGFloat(maxCount)))
                                }
                            }
                            .frame(height: 6)
                            Text("\(item.1)")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(Theme.inkFaint)
                                .frame(width: 24, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 观察

    private var observationSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("一些观察", note: "不是结论")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(snapshot.observations.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: 11) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent.opacity(0.65))
                            .padding(.top, 2)
                        Text(TagParser.highlight(text))
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.ink.opacity(0.84))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accentMist.opacity(0.66))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(0.09), lineWidth: 0.8)
            )
        }
    }

    // MARK: 片段

    private var highlightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("从这段时间里挑出的几段", note: "\(snapshot.highlights.count) 段")

            VStack(spacing: 9) {
                ForEach(snapshot.highlights) { memo in
                    Button {
                        app.select(.all)
                        app.selectedMemoID = memo.id
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateText.ageLabel(memo.createdAt))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                Text(DateText.absolute(memo.createdAt))
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .frame(width: 76, alignment: .leading)

                            Text(TagParser.highlight(memo.text))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.ink.opacity(0.82))
                                .lineSpacing(4)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 2)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.inkGhost)
                                .padding(.top, 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.card.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Theme.hairlineSoft, lineWidth: 0.7)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeading(_ text: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(note)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}

struct RhythmBars: View {
    let series: [(date: Date, count: Int)]
    let range: InsightRange

    private var maxCount: Int {
        max(series.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: range == .week ? 12 : 4) {
                ForEach(Array(series.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: range == .week ? 4 : 2, style: .continuous)
                            .fill(day.count > 0 ? Theme.accent.opacity(0.78) : Theme.field.opacity(0.7))
                            .frame(height: max(day.count > 0 ? 8 : 4, CGFloat(day.count) / CGFloat(maxCount) * 76))
                            .frame(maxWidth: .infinity)

                        if range == .week {
                            Text(weekday(day.date))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.inkFaint)
                        } else if index % 7 == 0 || index == series.count - 1 {
                            Text(dayLabel(day.date))
                                .font(.system(size: 8.5))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize()
                        } else {
                            Color.clear.frame(height: 10)
                        }
                    }
                }
            }
            .frame(height: 90)
        }
    }

    private func weekday(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[DateText.cal.component(.weekday, from: date) - 1]
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
