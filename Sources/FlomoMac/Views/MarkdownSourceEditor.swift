import AppKit
import SwiftUI

enum MarkdownInsertion: String, CaseIterable {
    case heading = "标题"
    case bold = "粗体"
    case italic = "斜体"
    case link = "链接"
    case bulletList = "无序列表"
    case orderedList = "有序列表"
    case checklist = "任务清单"
    case quote = "引用"
    case inlineCode = "行内代码"
    case codeBlock = "代码块"
    case table = "表格"

    var icon: String {
        switch self {
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .link: return "link"
        case .bulletList: return "list.bullet"
        case .orderedList: return "list.number"
        case .checklist: return "checklist"
        case .quote: return "text.quote"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .codeBlock: return "curlybraces"
        case .table: return "tablecells"
        }
    }
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let editor: Editor

    final class Editor {
        weak var view: MarkdownTextView?

        func insert(_ item: MarkdownInsertion) {
            guard let view, !view.hasMarkedText() else { return }
            view.window?.makeFirstResponder(view)
            view.apply(item)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.drawsBackground = false
        textView.textColor = NSColor(Theme.ink)
        textView.insertionPointColor = NSColor(Theme.accentDeep)
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        textView.defaultParagraphStyle = paragraphStyle
        textView.textContainerInset = NSSize(width: 16, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Markdown 正文")
        scrollView.documentView = textView
        editor.view = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text, !textView.hasMarkedText() else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            text.wrappedValue = view.string
        }
    }
}

final class MarkdownTextView: NSTextView {
    private var slashRange: NSRange?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, !hasMarkedText() {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": apply(.bold); return true
            case "i": apply(.italic); return true
            case "k": apply(.link); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let selection = selectedRange()
        let atEmptyLine = (string as NSString).lineRange(for: selection).length == 0 ||
            (string as NSString).substring(with: (string as NSString).lineRange(for: selection))
                .trimmingCharacters(in: .newlines).isEmpty
        let shouldShowMenu = event.characters == "/" && selection.length == 0 && !hasMarkedText() &&
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty && atEmptyLine

        super.keyDown(with: event)

        if shouldShowMenu, selectedRange().location == selection.location + 1 {
            showInsertMenu(replacing: NSRange(location: selection.location, length: 1))
        }
    }

    func apply(_ item: MarkdownInsertion, replacing explicitRange: NSRange? = nil) {
        let range = explicitRange ?? selectedRange()
        let source = string as NSString
        let selected = explicitRange == nil ? source.substring(with: range) : ""
        switch item {
        case .bold: wrap(selected, fallback: "粗体文字", before: "**", after: "**", range: range)
        case .italic: wrap(selected, fallback: "斜体文字", before: "*", after: "*", range: range)
        case .link: wrap(selected, fallback: "链接文字", before: "[", after: "](https://example.com)", range: range)
        case .inlineCode: wrap(selected, fallback: "代码", before: "`", after: "`", range: range)
        case .heading: prefixLine("## ", range: range, fromSlash: explicitRange != nil)
        case .bulletList: prefixLine("- ", range: range, fromSlash: explicitRange != nil)
        case .orderedList: prefixLine("1. ", range: range, fromSlash: explicitRange != nil)
        case .checklist: prefixLine("- [ ] ", range: range, fromSlash: explicitRange != nil)
        case .quote: prefixLine("> ", range: range, fromSlash: explicitRange != nil)
        case .codeBlock, .table:
            let opening = item == .codeBlock ? "```\n" : ""
            let closing = item == .codeBlock ? "\n```" : ""
            let content = item == .codeBlock
                ? (selected.isEmpty ? "代码" : selected)
                : "| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |"
            let before = range.location == 0 ? "" : "\n\n"
            let after = NSMaxRange(range) == source.length ? "\n" : "\n\n"
            replace(range, with: before + opening + content + closing + after,
                    selectAt: (before + opening).utf16.count,
                    length: item == .codeBlock ? content.utf16.count : 0)
        }
    }

    private func prefixLine(_ prefix: String, range: NSRange, fromSlash: Bool) {
        let start = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location
        let replacement = fromSlash ? range : NSRange(location: start, length: 0)
        let offset = fromSlash ? 0 : range.location - start
        replace(replacement, with: prefix, selectAt: prefix.utf16.count + offset, length: fromSlash ? 0 : range.length)
    }

    private func wrap(_ selected: String, fallback: String, before: String, after: String, range: NSRange) {
        let content = selected.isEmpty ? fallback : selected
        replace(range, with: before + content + after, selectAt: before.utf16.count, length: content.utf16.count)
    }

    private func replace(_ range: NSRange, with value: String, selectAt offset: Int, length: Int) {
        insertText(value, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + offset, length: length))
    }

    private func showInsertMenu(replacing range: NSRange) {
        guard let window else { return }
        let menu = NSMenu()
        for insertion in MarkdownInsertion.allCases {
            let item = NSMenuItem(title: insertion.rawValue, action: #selector(chooseInsertion(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: insertion.icon, accessibilityDescription: nil)
            menu.addItem(item)
        }
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let position = convert(window.convertFromScreen(caret), from: nil).origin
        slashRange = range
        menu.popUp(positioning: nil, at: position, in: self)
        slashRange = nil
    }

    @objc private func chooseInsertion(_ item: NSMenuItem) {
        guard let insertion = MarkdownInsertion(rawValue: item.title), let slashRange else { return }
        apply(insertion, replacing: slashRange)
    }
}
