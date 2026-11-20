import Foundation

enum DateText {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 2
        return c
    }

    static func startOfDay(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    static func dayKeyString(_ date: Date) -> String {
        dayKeyFormatter().string(from: date)
    }

    static func date(dayKey: String) -> Date? {
        dayKeyFormatter().date(from: dayKey)
    }

    private static func dayKeyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func stamp(_ date: Date, now: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            f.dateFormat = "HH:mm"
            return "昨天 " + f.string(from: date)
        }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            f.dateFormat = "M月d日 HH:mm"
            return f.string(from: date)
        }
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayHeader(_ date: Date, now: Date = .now) -> String {
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = (cal.component(.year, from: date) == cal.component(.year, from: now))
            ? "M月d日 EEEE" : "yyyy年M月d日"
        return f.string(from: date)
    }

    /// 详情页日期大字上方的一行：用于补足“今天/昨天”或星期，而不重复日期。
    static func dayKicker(_ date: Date, now: Date = .now) -> String {
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "d"
        return f.string(from: date)
    }

    static func monthName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: date)
    }

    static func full(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return f.string(from: date)
    }

    static func absolute(_ date: Date, now: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = (cal.component(.year, from: date) == cal.component(.year, from: now))
            ? "M月d日 HH:mm" : "yyyy年M月d日"
        return f.string(from: date)
    }

    static func ageLabel(_ date: Date, now: Date = .now) -> String {
        let days = cal.dateComponents([.day], from: startOfDay(date), to: startOfDay(now)).day ?? 0
        if days <= 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 周前" }
        if days < 365 { return "\(days / 30) 个月前" }

        let years = days / 365
        let sameMonth = cal.component(.month, from: date) == cal.component(.month, from: now)
        let sameDay = cal.component(.day, from: date) == cal.component(.day, from: now)
        if sameMonth && sameDay {
            return years == 1 ? "去年今天" : "\(years) 年前的今天"
        }
        return years == 1 ? "一年前" : "\(years) 年前"
    }

    static func startOfThisWeek(now: Date = .now) -> Date {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: comps) ?? startOfDay(now)
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        cal.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }
}
