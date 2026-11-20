import Foundation

enum MarkdownHTML {
    static func render(_ markdown: String) -> String {
        guard let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        ) else {
            return "<pre>\(escape(markdown))</pre>"
        }

        var html = ""
        var blocks: [Block] = []
        for run in parsed.runs {
            let path = Array((run.presentationIntent?.components ?? []).reversed())
            let commonCount = zip(blocks, path).prefix { $0.0.id == $0.1.identity }.count
            while blocks.count > commonCount {
                if let block = blocks.popLast() {
                    html += block.close
                }
            }

            let startsParagraph = path.count > commonCount
            for (index, component) in path.enumerated().dropFirst(commonCount) {
                let next = path.indices.contains(index + 1) ? path[index + 1].kind : nil
                if case .tableCell(let column) = component.kind, let row = blocks.indices.last {
                    html += blocks[row].fillCells(upTo: column)
                    blocks[row].cellsWritten = column + 1
                }
                let block = Block(component, parent: path.prefix(index), next: next)
                html += block.open
                blocks.append(block)
            }

            var raw = String(parsed[run.range].characters)
            if case .thematicBreak? = path.last?.kind { continue }
            if case .codeBlock? = path.last?.kind {
                html += escape(raw)
                continue
            }
            if startsParagraph, case .paragraph? = path.last?.kind, path.count > 1,
               case .listItem = path[path.count - 2].kind {
                let marker = raw.prefix(3).lowercased()
                if (marker == "[x]" || marker == "[ ]"),
                   raw.count == 3 || raw.dropFirst(3).first?.isWhitespace == true {
                    html += marker == "[x]" ? "<input type=\"checkbox\" checked disabled>" : "<input type=\"checkbox\" disabled>"
                    raw = String(raw.dropFirst(3))
                }
            }

            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.lineBreak) {
                html += "<br>"
                continue
            }

            if let url = run.imageURL, url.scheme?.lowercased() == "https", url.host != nil {
                html += "<img src=\"\(escape(url.absoluteString))\" alt=\"\(escape(raw))\">"
                continue
            }

            var fragment = escape(raw)
            if inline.contains(.code) { fragment = "<code>\(fragment)</code>" }
            if inline.contains(.strikethrough) { fragment = "<del>\(fragment)</del>" }
            if inline.contains(.emphasized) { fragment = "<em>\(fragment)</em>" }
            if inline.contains(.stronglyEmphasized) { fragment = "<strong>\(fragment)</strong>" }
            if let url = run.link, isExternalLink(url) || memoLinkID(url) != nil {
                fragment = "<a href=\"\(escape(url.absoluteString))\">\(fragment)</a>"
            }
            html += fragment
        }
        return html + blocks.reversed().map(\.close).joined()
    }

    static func isExternalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (["http", "https"].contains(scheme) && url.host != nil) || scheme == "mailto"
    }

    static func memoLinkID(_ url: URL) -> UUID? {
        guard AppBrand.acceptsURLScheme(url.scheme), url.host?.lowercased() == "memo",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private struct Block {
        let id: Int
        let open: String
        let closingTag: String
        var cellsWritten = 0
        private var columnCount = 0
        private var blankCell = ""

        var close: String { fillCells(upTo: columnCount) + closingTag }

        func fillCells(upTo column: Int) -> String {
            String(repeating: blankCell, count: max(0, column - cellsWritten))
        }

        init(
            _ component: PresentationIntent.IntentType,
            parent: ArraySlice<PresentationIntent.IntentType>,
            next: PresentationIntent.Kind?
        ) {
            id = component.identity
            switch component.kind {
            case .paragraph: (open, closingTag) = ("<p>", "</p>")
            case .header(let level): (open, closingTag) = ("<h\(level)>", "</h\(level)>")
            case .blockQuote: (open, closingTag) = ("<blockquote>", "</blockquote>")
            case .unorderedList: (open, closingTag) = ("<ul>", "</ul>")
            case .orderedList:
                if case .listItem(let ordinal)? = next {
                    open = "<ol start=\"\(ordinal)\">"
                } else {
                    open = "<ol>"
                }
                closingTag = "</ol>"
            case .listItem: (open, closingTag) = ("<li>", "</li>")
            case .codeBlock: (open, closingTag) = ("<pre><code>", "</code></pre>")
            case .thematicBreak: (open, closingTag) = ("<hr>", "")
            case .table: (open, closingTag) = ("<table>", "</table>")
            case .tableHeaderRow, .tableRow:
                (open, closingTag) = ("<tr>", "</tr>")
                if case .table(let columns)? = parent.last?.kind {
                    columnCount = columns.count
                    blankCell = component.kind == .tableHeaderRow ? "<th></th>" : "<td></td>"
                }
            case .tableCell(let index):
                let header = parent.last?.kind == .tableHeaderRow
                let tag = header ? "th" : "td"
                var alignment = ""
                if case .table(let columns)? = parent.dropLast().last?.kind, columns.indices.contains(index) {
                    switch columns[index].alignment {
                    case .right: alignment = " class=\"right\""
                    case .center: alignment = " class=\"center\""
                    default: break
                    }
                }
                (open, closingTag) = ("<\(tag)\(alignment)>", "</\(tag)>")
            default: (open, closingTag) = ("", "")
            }
        }
    }
}
