import Foundation

struct AIReviewBatch {
    struct Source {
        let memoID: UUID
        let day: String
        let text: String
    }

    let firstDay: String
    let lastDay: String
    let observationStart: String
    let sources: [Source]
    let omittedCount: Int
    let hasExcerpts: Bool

    var periodLabel: String { "\(firstDay) 至 \(lastDay)" }

    static func make(from memos: [Memo], now: Date = .now) -> Self {
        let calendar = DateText.cal
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let observationStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recent = memos.filter { $0.createdAt >= start && $0.createdAt <= now }
            .sorted { $0.createdAt > $1.createdAt }

        var sources: [Source] = []
        var remaining = 36_000
        var eligible = 0
        var hasExcerpts = false
        for memo in recent {
            let text = memo.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            eligible += 1
            guard sources.count < 60, remaining > 0 else { continue }
            let excerpt = String(text.prefix(min(900, remaining)))
            sources.append(Source(memoID: memo.id, day: DateText.dayKeyString(memo.createdAt), text: excerpt))
            hasExcerpts = hasExcerpts || excerpt != text
            remaining -= excerpt.count
        }
        return Self(
            firstDay: DateText.dayKeyString(start),
            lastDay: DateText.dayKeyString(today),
            observationStart: DateText.dayKeyString(observationStart),
            sources: sources,
            omittedCount: eligible - sources.count,
            hasExcerpts: hasExcerpts
        )
    }
}

struct AIReviewReport: Codable {
    struct Section: Codable {
        let heading: String
        let body: String
    }

    struct ArticleIdea: Codable {
        let title: String
        let angle: String
        let sections: [Section]
        let memoIDs: [UUID]

        func markdown(sources: [Memo]) -> String {
            let chapters = sections.map { section in
                "## \(Self.escape(section.heading))\n\n\(Self.escape(section.body))"
            }
            let links = sources.enumerated().map { index, memo in
                "- [\(DateText.dayKeyString(memo.createdAt)) · 记录 \(index + 1)](\(AppBrand.urlScheme)://memo/\(memo.id.uuidString))"
            }
            return (chapters + ["## 素材出处\n\n" + links.joined(separator: "\n")])
                .joined(separator: "\n\n") + "\n"
        }

        private static func escape(_ text: String) -> String {
            let syntax = Set("\\`*_{}[]()#+-.!<>~|")
            return text.reduce(into: "") { escaped, character in
                if syntax.contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
        }
    }

    struct Observation: Codable {
        let title: String
        let detail: String
        let suggestion: String
        let memoIDs: [UUID]
    }

    let generatedAt: Date
    let periodLabel: String
    let sourceCount: Int
    let articleIdeas: [ArticleIdea]
    let observations: [Observation]
}

struct AIReviewModelOutput: Decodable {
    struct Idea: Decodable {
        let title: String
        let angle: String
        let sections: [AIReviewReport.Section]
        let sourceIDs: [Int]
    }

    struct Observation: Decodable {
        let title: String
        let detail: String
        let suggestion: String
        let sourceIDs: [Int]
    }

    let articleIdeas: [Idea]
    let observations: [Observation]

    func report(for batch: AIReviewBatch, generatedAt: Date = .now) throws -> AIReviewReport {
        func sources(for ids: [Int]) -> [AIReviewBatch.Source]? {
            let ordered = ids.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
            guard (2...5).contains(ordered.count),
                  ordered.allSatisfy({ $0 > 0 && $0 <= batch.sources.count }) else { return nil }
            return ordered.map { batch.sources[$0 - 1] }
        }

        func clean(_ value: String, maxLength: Int) -> String {
            String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        }

        let ideas: [AIReviewReport.ArticleIdea] = articleIdeas.compactMap { idea in
            let title = clean(idea.title.split(whereSeparator: \.isNewline).joined(separator: " "), maxLength: 90)
            let angle = clean(idea.angle, maxLength: 300)
            let sections = idea.sections.prefix(3).map { section in
                AIReviewReport.Section(
                    heading: clean(section.heading.split(whereSeparator: \.isNewline).joined(separator: " "), maxLength: 90),
                    body: clean(section.body, maxLength: 1_000)
                )
            }.filter { !$0.heading.isEmpty && !$0.body.isEmpty }
            guard !title.isEmpty, !angle.isEmpty, sections.count >= 2,
                  let sources = sources(for: idea.sourceIDs) else { return nil }
            return AIReviewReport.ArticleIdea(title: title, angle: angle, sections: sections, memoIDs: sources.map(\.memoID))
        }

        let findings: [AIReviewReport.Observation] = observations.compactMap { observation in
            let title = clean(observation.title, maxLength: 90)
            let detail = clean(observation.detail, maxLength: 500)
            guard !title.isEmpty, !detail.isEmpty, let sources = sources(for: observation.sourceIDs),
                  sources.allSatisfy({ $0.day >= batch.observationStart }),
                  Set(sources.map(\.day)).count >= 2 else { return nil }
            return AIReviewReport.Observation(
                title: title, detail: detail, suggestion: clean(observation.suggestion, maxLength: 300),
                memoIDs: sources.map(\.memoID)
            )
        }

        if ideas.isEmpty, findings.isEmpty, !articleIdeas.isEmpty || !observations.isEmpty {
            throw AIReviewError.invalidSources
        }
        return AIReviewReport(
            generatedAt: generatedAt, periodLabel: batch.periodLabel, sourceCount: batch.sources.count,
            articleIdeas: Array(ideas.prefix(2)), observations: Array(findings.prefix(2))
        )
    }
}
