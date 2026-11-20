import Foundation

enum MarkdownTransfer {
    static func export(memos: [Memo]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"

        let generated = DateFormatter()
        generated.locale = Locale(identifier: "zh_CN")
        generated.dateFormat = "yyyy年M月d日 HH:mm"

        var out = "# \(AppBrand.name) 笔记备份\n\n"
        out += "导出时间：\(generated.string(from: .now))\n"
        out += "共 \(memos.count) 条\n\n---\n\n"

        for memo in memos.sorted(by: { $0.createdAt < $1.createdAt }) {
            out += "## \(f.string(from: memo.createdAt))"
            if memo.isPinned { out += " · 置顶" }
            out += "\n\n\(memo.text)\n\n"
        }
        return out
    }

    /// 兼容本 App 与 iPhone 版导出的格式：`## yyyy-MM-dd HH:mm` 分节。
    /// 也接受没有日期标题的普通 Markdown，每条按分隔线拆。
    static func parse(_ text: String) -> [(text: String, date: Date)] {
        let blocks = text.components(separatedBy: "\n## ")
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "zh_CN")
        f2.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var out: [(String, Date)] = []
        for (index, rawBlock) in blocks.enumerated() {
            var block = rawBlock
            if index == 0 {
                if let range = block.range(of: "\n## ") {
                    block = String(block[range.upperBound...])
                } else {
                    continue
                }
            }

            let lines = block.components(separatedBy: "\n")
            guard let first = lines.first else { continue }
            let header = first.trimmingCharacters(in: .whitespaces)
            let date = f.date(from: header) ?? f2.date(from: header) ?? .now
            let body = lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                out.append((body, date))
            }
        }

        if out.isEmpty {
            let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                let chunks = plain.components(separatedBy: "\n---\n")
                for chunk in chunks {
                    let body = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty { out.append((body, .now)) }
                }
            }
        }

        return out
    }
}
