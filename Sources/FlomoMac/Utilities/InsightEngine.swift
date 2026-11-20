import Foundation

struct InsightSnapshot {
    let range: InsightRange
    let start: Date
    let end: Date
    let memos: [Memo]
    let previousCount: Int?

    let activeDays: Int
    let tagCounts: [(String, Int)]
    let busiestWeekday: String?
    let totalCharacters: Int
    let dayCounts: [Date: Int]
    let series: [(date: Date, count: Int)]
    let observations: [String]
    let highlights: [Memo]

    var count: Int { memos.count }

    var periodLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        if DateText.cal.isDate(start, equalTo: end, toGranularity: .year) {
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        f.dateFormat = "yyyy年M月d日"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    var averagePerActiveDay: Double {
        activeDays == 0 ? 0 : Double(count) / Double(activeDays)
    }
}

enum InsightEngine {
    static func make(range: InsightRange, memos: [Memo], now: Date = .now) -> InsightSnapshot {
        let end = DateText.startOfDay(now)
        let allStart = memos.map { DateText.startOfDay($0.createdAt) }.min() ?? end
        let start: Date
        let previousStart: Date?
        let previousEnd: Date?

        switch range {
        case .week:
            start = DateText.startOfThisWeek(now: now)
            previousStart = DateText.cal.date(byAdding: .day, value: -7, to: start)
            previousEnd = DateText.cal.date(byAdding: .day, value: -1, to: start)
        case .month:
            start = DateText.cal.date(byAdding: .day, value: -29, to: end) ?? end
            previousStart = DateText.cal.date(byAdding: .day, value: -60, to: end)
            previousEnd = DateText.cal.date(byAdding: .day, value: -30, to: end)
        case .all:
            start = allStart
            previousStart = nil
            previousEnd = nil
        }

        let current = memos.filter {
            let day = DateText.startOfDay($0.createdAt)
            return day >= start && day <= end
        }.sorted { $0.createdAt > $1.createdAt }

        var previousCount: Int?
        if let previousStart, let previousEnd {
            previousCount = memos.filter {
                let day = DateText.startOfDay($0.createdAt)
                return day >= previousStart && day <= previousEnd
            }.count
        }

        var tagCounts: [String: Int] = [:]
        for memo in current {
            for tag in Set(memo.tags) { tagCounts[tag, default: 0] += 1 }
        }
        let sortedTags = tagCounts
            .map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }

        var dayCounts: [Date: Int] = [:]
        for memo in current {
            dayCounts[DateText.startOfDay(memo.createdAt), default: 0] += 1
        }

        let weekdayCounts = Dictionary(grouping: current) {
            DateText.cal.component(.weekday, from: $0.createdAt)
        }.mapValues(\.count)
        let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let busiestWeekday = weekdayCounts.max { $0.value < $1.value }.map { weekdayNames[$0.key] }

        let days = seriesDays(from: start, to: end, all: range == .all)
        let series = days.map { day in
            (date: day, count: dayCounts[day] ?? 0)
        }

        let totalCharacters = current.reduce(0) { $0 + $1.text.count }

        var observations: [String] = []
        if current.isEmpty {
            observations.append("这段时间没有留下记录。空白也算一种状态。")
        } else {
            observations.append("留下了 \(current.count) 条记录，分布在 \(dayCounts.count) 天里。")

            if let busiestWeekday, let top = weekdayCounts.max(by: { $0.value < $1.value }) {
                observations.append("\(busiestWeekday)最常动笔，一共 \(top.value) 条。")
            }

            if let first = sortedTags.first {
                if sortedTags.count > 1 {
                    observations.append("出现最多的线索是 #\(first.0)，\(first.1) 条；其次是 #\(sortedTags[1].0)。")
                } else {
                    observations.append("这段时间只有一个主题：#\(first.0)。")
                }
            }

            if let previousCount, previousCount > 0 {
                let delta = current.count - previousCount
                if delta > 0 {
                    observations.append("比上一段时间多写了 \(delta) 条，笔头在变热。")
                } else if delta < 0 {
                    observations.append("比上一段时间少了 \(-delta) 条，慢一点也没关系。")
                } else {
                    observations.append("和上一段时间一样多，节奏很稳。")
                }
            }

            if let latest = current.first {
                let gap = DateText.daysBetween(latest.createdAt, end)
                if gap >= 3 {
                    observations.append("最近一次记录在 \(gap) 天前，也许可以坐下来说两句。")
                }
            }
        }

        return InsightSnapshot(
            range: range,
            start: start,
            end: end,
            memos: current,
            previousCount: previousCount,
            activeDays: dayCounts.count,
            tagCounts: sortedTags,
            busiestWeekday: busiestWeekday,
            totalCharacters: totalCharacters,
            dayCounts: dayCounts,
            series: series,
            observations: Array(observations.prefix(5)),
            highlights: pickHighlights(from: current)
        )
    }

    private static func seriesDays(from start: Date, to end: Date, all: Bool) -> [Date] {
        if all {
            let from = DateText.cal.date(byAdding: .day, value: -89, to: end) ?? end
            return stride(from: 0, through: DateText.daysBetween(from, end), by: 1).compactMap {
                DateText.cal.date(byAdding: .day, value: $0, to: from)
            }
        }
        let span = max(0, DateText.daysBetween(start, end))
        return stride(from: 0, through: span, by: 1).compactMap {
            DateText.cal.date(byAdding: .day, value: $0, to: start)
        }
    }

    private static func pickHighlights(from memos: [Memo]) -> [Memo] {
        guard !memos.isEmpty else { return [] }
        var picks: [Memo] = []
        var seen = Set<UUID>()

        func add(_ memo: Memo?) {
            guard let memo, seen.insert(memo.id).inserted else { return }
            picks.append(memo)
        }

        add(memos.first)
        add(memos.max { $0.tags.count < $1.tags.count })
        add(memos.max { $0.text.count < $1.text.count })
        add(memos.dropFirst(memos.count / 2).first)

        return Array(picks.prefix(3))
    }
}
