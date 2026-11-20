import AppKit
import SwiftUI

struct MemoTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange?
    let editor: Editor
    let onSuggestionKey: (SuggestionKey) -> Bool

    enum SuggestionKey {
        case previous, next, accept, dismiss
    }

    final class Editor {
        weak var view: NSTextView?

        func focus() {
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }

        func replace(_ range: NSRange, with string: String) {
            guard let view, !view.hasMarkedText() else { return }
            focus()
            view.insertText(string, replacementRange: range)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: 17)
        view.textColor = NSColor(Theme.ink)
        view.insertionPointColor = NSColor(Theme.accentDeep)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        view.defaultParagraphStyle = style
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.setAccessibilityLabel("记录正文")
        editor.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.editor = self
        guard let view = scroll.documentView as? NSTextView, view.string != text,
              !view.hasMarkedText() else { return }
        coordinator.updating = true
        view.string = text
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        coordinator.updating = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: MemoTextEditor
        var updating = false

        init(editor: MemoTextEditor) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !updating, !view.hasMarkedText() else { return }
            editor.text = view.string
            editor.selection = view.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !updating, !view.hasMarkedText() else { return }
            editor.selection = view.selectedRange()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText(),
                  NSApp.currentEvent?.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty == true
            else { return false }

            switch selector {
            case #selector(NSResponder.moveUp(_:)): return editor.onSuggestionKey(.previous)
            case #selector(NSResponder.moveDown(_:)): return editor.onSuggestionKey(.next)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                return editor.onSuggestionKey(.accept)
            case #selector(NSResponder.cancelOperation(_:)): return editor.onSuggestionKey(.dismiss)
            default: return false
            }
        }
    }
}
