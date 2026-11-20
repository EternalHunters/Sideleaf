import SwiftUI

struct ContributionGrid: View {
    let counts: [Date: Int]
    var weeks: Int = 13
    var tint: Color = Theme.accent

    private let gap: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(columns, id: \.monday) { week in
                    VStack(spacing: gap) {
                        ForEach(week.days, id: \.date) { day in
                            cell(day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            monthRow
        }
    }

    private func cell(_ day: Day) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(fill(day))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(tint.opacity(day.count > 0 ? 0.9 : 0.4), lineWidth: 1.2)
                }
            }
            .opacity(day.isFuture ? 0 : 1)
            .help(helpText(day))
    }

    private func fill(_ day: Day) -> Color {
        switch day.count {
        case 0: return Theme.field.opacity(0.64)
        case 1: return tint.opacity(0.28)
        case 2: return tint.opacity(0.48)
        case 3: return tint.opacity(0.68)
        default: return tint.opacity(0.9)
        }
    }

    private func helpText(_ day: Day) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        if day.isFuture { return "" }
        return day.count == 0 ? "\(f.string(from: day.date)) 没有记录" : "\(f.string(from: day.date)) \(day.count) 条"
    }

    private var monthRow: some View {
        HStack(spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.element.monday) { index, _ in
                ZStack(alignment: .leading) {
                    if let label = monthLabel(at: index) {
                        Text(label)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 12)
    }

    private func monthLabel(at index: Int) -> String? {
        guard index < columns.count, let first = columns[index].days.first else { return nil }
        let month = DateText.cal.component(.month, from: first.date)
        if index == 0 { return "\(month)月" }
        guard let previous = columns[index - 1].days.first else { return "\(month)月" }
        return DateText.cal.component(.month, from: previous.date) == month ? nil : "\(month)月"
    }

    private struct Day {
        let date: Date
        let count: Int
        let isToday: Bool
        let isFuture: Bool
    }

    private struct Week {
        let monday: Date
        let days: [Day]
    }

    private var today: Date { DateText.startOfDay(.now) }

    static func windowStart(weeks: Int = 13, today: Date = DateText.startOfDay(.now)) -> Date {
        let cal = DateText.cal
        let offset = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -offset, to: today) ?? today
        return cal.date(byAdding: .day, value: -7 * (weeks - 1), to: monday) ?? monday
    }

    private var columns: [Week] {
        let cal = DateText.cal
        let firstMonday = Self.windowStart(weeks: weeks, today: today)

        return (0..<weeks).map { weekIndex in
            let days = (0..<7).map { dayIndex -> Day in
                let date = cal.date(byAdding: .day, value: weekIndex * 7 + dayIndex, to: firstMonday) ?? firstMonday
                return Day(
                    date: date,
                    count: counts[date] ?? 0,
                    isToday: cal.isDate(date, inSameDayAs: today),
                    isFuture: date > today
                )
            }
            return Week(monday: days[0].date, days: days)
        }
    }
}
