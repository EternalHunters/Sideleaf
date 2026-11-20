import Foundation
import SwiftUI

/// flomo 的标签长在正文里，例如 `#读书/商业`。
/// 解析规则要同时容忍中文、层级和 `C#` 这种“假标签”。
enum TagParser {
    static func isTagChar(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return c == "_" || c == "-" || c == "/"
    }

    static func isBoundary(_ c: Character) -> Bool {
        c.isWhitespace || c.isPunctuation || c.isSymbol
    }

    struct Completion: Equatable {
        let prefix: String
        let range: NSRange
    }

    static func completion(in text: String, selection: NSRange?) -> Completion? {
        let utf16 = text.utf16
        guard let selection, selection.length == 0, selection.location >= 0,
              let index = utf16.index(utf16.startIndex, offsetBy: selection.location, limitedBy: utf16.endIndex),
              let caret = index.samePosition(in: text) else { return nil }

        var start = caret
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isTagChar(text[previous]) else { break }
            start = previous
        }
        guard start > text.startIndex else { return nil }
        let hash = text.index(before: start)
        guard text[hash] == "#",
              hash == text.startIndex || isBoundary(text[text.index(before: hash)]) else { return nil }

        var end = caret
        while end < text.endIndex, isTagChar(text[end]) {
            end = text.index(after: end)
        }
        return Completion(prefix: String(text[start..<caret]), range: NSRange(hash..<end, in: text))
    }

    static func tags(in text: String) -> [String] {
        let chars = Array(text)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i == 0 || isBoundary(chars[i - 1]) {
                var j = i + 1
                var buffer = ""
                while j < chars.count, isTagChar(chars[j]) {
                    buffer.append(chars[j])
                    j += 1
                }
                if !buffer.isEmpty {
                    out.append(buffer)
                    i = j
                    continue
                }
            }
            i += 1
        }
        return out
    }

    static func uniqueTags(in text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in tags(in: text) where seen.insert(tag).inserted {
            out.append(tag)
        }
        return out
    }

    static func removingTags(from text: String) -> String {
        tags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: "#\(tag)", with: "")
        }
    }

    /// 给正文里的标签着色；同时用 word joiner 防止标签被折行拆开。
    static func highlight(_ text: String, color: Color = Theme.tag) -> AttributedString {
        let chars = Array(text)
        var result = AttributedString()
        var plain = ""
        var i = 0

        while i < chars.count {
            if chars[i] == "#", i == 0 || isBoundary(chars[i - 1]) {
                var j = i + 1
                var buffer = ""
                while j < chars.count, isTagChar(chars[j]) {
                    buffer.append(chars[j])
                    j += 1
                }
                if !buffer.isEmpty {
                    if !plain.isEmpty {
                        result.append(AttributedString(plain))
                        plain = ""
                    }
                    var segment = AttributedString(glueTag(buffer))
                    segment.foregroundColor = color
                    result.append(segment)
                    i = j
                    continue
                }
            }
            plain.append(chars[i])
            i += 1
        }
        if !plain.isEmpty { result.append(AttributedString(plain)) }
        return result
    }

    static func glueTag(_ tag: String) -> String {
        let joiner = "\u{2060}"
        let body = Array(tag).map(String.init).joined(separator: joiner)
        return "#" + joiner + body
    }

    static func ancestry(of tag: String) -> [String] {
        var out: [String] = []
        var path = ""
        for part in tag.split(separator: "/") {
            path = path.isEmpty ? String(part) : path + "/" + part
            out.append(path)
        }
        return out
    }

    /// 一条笔记只给父标签记一次账。
    /// 同时写了 `#产品` 和 `#产品/决策` 时，父标签不能加两次。
    static func countedByMemo(_ memoTagLists: [[String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for tags in memoTagLists {
            var seen = Set<String>()
            for tag in tags {
                for path in ancestry(of: tag) where seen.insert(path).inserted {
                    counts[path, default: 0] += 1
                }
            }
        }
        return counts
    }

    static func tree(_ counts: [String: Int]) -> [TagNode] {
        let root = TagNode(name: "", path: "", count: 0)
        for path in counts.keys.sorted() {
            var node = root
            var acc = ""
            for part in path.split(separator: "/") {
                let name = String(part)
                acc = acc.isEmpty ? name : acc + "/" + name
                if let child = node.children[name] {
                    node = child
                } else {
                    let child = TagNode(name: name, path: acc, count: counts[acc] ?? 0)
                    node.children[name] = child
                    node = child
                }
            }
        }
        return root.sortedChildren
    }

    static func roots(for memos: [Memo]) -> [TagNode] {
        tree(countedByMemo(memos.map(\.tags)))
    }
}

final class TagNode: Identifiable {
    let name: String
    let path: String
    let count: Int
    var children: [String: TagNode] = [:]

    var id: String { path }

    init(name: String, path: String, count: Int) {
        self.name = name
        self.path = path
        self.count = count
    }

    var sortedChildren: [TagNode] {
        children.values.sorted {
            $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
        }
    }
}
