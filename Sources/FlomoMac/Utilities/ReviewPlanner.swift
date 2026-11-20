import Foundation

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 每日回顾的取数规则：按时间距离分桶，让旧记忆也有登场机会。
enum ReviewPlanner {
    private struct Bucket {
        let lower: Int
        let upper: Int
        let weight: Double
    }

    private static let buckets: [Bucket] = [
        Bucket(lower: 1, upper: 7, weight: 0.10),
        Bucket(lower: 8, upper: 30, weight: 0.18),
        Bucket(lower: 31, upper: 365, weight: 0.32),
        Bucket(lower: 366, upper: 1_000_000, weight: 0.40),
    ]

    static func pick(from memos: [Memo], count: Int, day: Date) -> [UUID] {
        let today = DateText.startOfDay(day)
        let pool = memos.filter { $0.createdAt < today }
        guard !pool.isEmpty, count > 0 else { return [] }

        var grouped: [[Memo]] = Array(repeating: [], count: buckets.count)
        for memo in pool {
            let age = DateText.daysBetween(memo.createdAt, today)
            for (i, bucket) in buckets.enumerated() where age >= bucket.lower && age <= bucket.upper {
                grouped[i].append(memo)
                break
            }
        }

        let nonEmpty = grouped.indices.filter { !grouped[$0].isEmpty }
        guard !nonEmpty.isEmpty else { return [] }

        var quota = Array(repeating: 0, count: buckets.count)
        var remaining = min(count, pool.count)

        if remaining > 0,
           let oldest = nonEmpty.max(by: { buckets[$0].upper < buckets[$1].upper }) {
            quota[oldest] = 1
            remaining -= 1
        }

        while remaining > 0 {
            var best = -1
            var bestGap = -Double.infinity
            for i in nonEmpty {
                guard grouped[i].count - quota[i] > 0 else { continue }
                let gap = Double(count) * buckets[i].weight - Double(quota[i])
                if gap > bestGap {
                    bestGap = gap
                    best = i
                }
            }
            guard best >= 0 else { break }
            quota[best] += 1
            remaining -= 1
        }

        var picks: [Memo] = []
        for i in nonEmpty where quota[i] > 0 {
            let seed = seed(day: today, bucket: i)
            var generator = SeededGenerator(seed: seed)
            picks.append(contentsOf: grouped[i].shuffled(using: &generator).prefix(quota[i]))
        }

        picks.sort { $0.createdAt > $1.createdAt }
        return picks.map(\.id)
    }

    private static func seed(day: Date, bucket: Int) -> UInt64 {
        let days = Int(day.timeIntervalSince1970 / 86_400)
        return UInt64(bitPattern: Int64(days)) &* 0x1_0000_0001_B3 &+ UInt64(bucket &* 0x9E37)
    }

    static func streak(in reviews: [DailyReview], now: Date = .now) -> Int {
        let done = Set(reviews.filter(\.isCompleted).map { DateText.startOfDay($0.day) })
        guard !done.isEmpty else { return 0 }

        var cursor = DateText.startOfDay(now)
        if !done.contains(cursor) {
            cursor = DateText.cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var n = 0
        while done.contains(cursor) {
            n += 1
            cursor = DateText.cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return n
    }
}
