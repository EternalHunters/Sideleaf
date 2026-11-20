import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ComposerView: View {
    static let quickCaptureSize = CGSize(width: 432, height: 452)

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]

    let request: ComposerRequest
    var quickCapture: QuickCaptureMenu? = nil

    @State private var text = ""
    @State private var images: [Data] = []
    @State private var loaded = false
    @State private var showImagePicker = false
    @State private var hoveringSave = false
    @State private var memoEditor = MemoTextEditor.Editor()
    @State private var selection: NSRange?
    @State private var suppressedCompletion: TagParser.Completion?
    @State private var selectedTagIndex = 0
    @State private var saveError: String?

    private var isQuickCapture: Bool { quickCapture != nil }

    private var editingMemo: Memo? {
        guard let id = request.memoID else { return nil }
        return memos.first(where: { $0.id == id })
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    private var rankedTags: [String] {
        TagParser.countedByMemo(memos.map(\.tags))
            .sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            .map(\.key)
    }

    private var completion: TagParser.Completion? {
        TagParser.completion(in: text, selection: selection)
    }

    private var activeCompletion: TagParser.Completion? {
        completion == suppressedCompletion ? nil : completion
    }

    private func matches(for completion: TagParser.Completion) -> [String] {
        let tags = rankedTags
        guard !completion.prefix.isEmpty else { return tags }
        return tags.filter { $0.localizedCaseInsensitiveContains(completion.prefix) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairlineSoft).frame(height: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    editor
                    if let activeCompletion {
                        tagSuggestions(matches(for: activeCompletion))
                    } else if !isQuickCapture {
                        let used = Set(TagParser.tags(in: text))
                        let commonTags = Array(rankedTags.lazy.filter { !used.contains($0) }.prefix(7))
                        if !commonTags.isEmpty { tagStrip(commonTags) }
                    }
                    if !images.isEmpty { imageStrip }
                    if let saveError {
                        Text(saveError)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(.horizontal, isQuickCapture ? 16 : 24)
                .padding(.vertical, isQuickCapture ? 12 : 18)
            }

            Rectangle().fill(Theme.hairlineSoft).frame(height: 0.7)
            footer
        }
        .frame(
            width: isQuickCapture ? Self.quickCaptureSize.width : 680,
            height: isQuickCapture ? Self.quickCaptureSize.height : 500
        )
        .background(Theme.bg)
        .onAppear(perform: load)
        .onChange(of: completion) {
            suppressedCompletion = nil
            selectedTagIndex = 0
        }
        .onChange(of: quickCapture?.focusRequest) { memoEditor.focus() }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let data = ImageTools.readSecurityScoped(url) {
                    images.append(ImageTools.compress(data))
                }
            }
        }
        .onExitCommand { handleEscape() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if isQuickCapture {
                HStack(spacing: 8) {
                    FlomoMark(size: 23)
                    Text("快速记录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(editingMemo == nil ? "新记录" : "编辑记录")
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(editingMemo == nil ? "现在" : DateText.stamp(editingMemo?.createdAt ?? .now))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft)
                            .clipShape(Capsule())
                    }
                    Text(editingMemo == nil ? "先写下来，整理可以稍后再做" : "改动会在完成时保存")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkFaint)
                }
            }

            Spacer()

            if let quickCapture {
                let title = quickCapture.isPinned ? "取消固定小窗" : "固定小窗"
                Button(action: quickCapture.togglePin) {
                    Image(systemName: quickCapture.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(quickCapture.isPinned ? Theme.accentDeep : Theme.inkSoft)
                        .frame(width: 28, height: 28)
                        .background(
                            quickCapture.isPinned ? Theme.accentSoft : Theme.field.opacity(0.65),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(quickCapture.isPinned ? .isSelected : [])
                .help(title)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.field.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .help("关闭 Esc")
        }
        .padding(.horizontal, isQuickCapture ? 16 : 22)
        .padding(.top, isQuickCapture ? 13 : 20)
        .padding(.bottom, isQuickCapture ? 10 : 15)
    }

    // MARK: 输入

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card.opacity(0.8))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 0.7)

            if text.isEmpty {
                Text(isQuickCapture ? "此刻在想什么…" : "此刻在想什么…\n\n可以只写一句。")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkGhost)
                    .lineSpacing(6)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            MemoTextEditor(text: $text, selection: $selection, editor: memoEditor, onSuggestionKey: handleSuggestionKey)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
        }
        .frame(height: isQuickCapture
            ? (activeCompletion == nil ? 290 : 160)
            : (activeCompletion == nil ? 228 : 176))
    }

    private func tagSuggestions(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("现有标签")
                .font(Theme.captionMedium)
                .foregroundStyle(Theme.inkSoft)
                .accessibilityAddTraits(.isHeader)

            if tags.isEmpty {
                Text("无匹配标签，可以继续输入以创建新标签")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                                Button { insertTag(tag) } label: {
                                    Label(tag, systemImage: "number")
                                        .font(Theme.captionMedium)
                                        .foregroundStyle(Theme.accentDeep)
                                        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
                                        .padding(.horizontal, 9)
                                        .background(
                                            index == selectedTagIndex ? Theme.accentSoft : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("#" + tag)
                                .accessibilityAddTraits(index == selectedTagIndex ? .isSelected : [])
                                .id(tag)
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: CGFloat(min(tags.count, 4) * 28 + 8))
                    .onChange(of: selectedTagIndex) {
                        if tags.indices.contains(selectedTagIndex) {
                            proxy.scrollTo(tags[selectedTagIndex])
                        }
                    }
                }
                .flomoCard(radius: 9)
            }
        }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    if let image = NSImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 78, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Button {
                                images.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.42))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                        }
                    }
                }

                Button { showImagePicker = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("继续添加")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 78, height: 78)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Theme.hairline)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private func tagStrip(_ suggestedTags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用标签")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .tracking(0.6)

            FlowLayout(spacing: 7) {
                ForEach(suggestedTags, id: \.self) { tag in
                    Button { insertTag(tag) } label: {
                        HStack(spacing: 4) {
                            Text("#" + tag)
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                                .opacity(0.55)
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tag)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.accentSoft.opacity(0.7))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 12) {
            if isQuickCapture {
                Button(action: beginTag) {
                    Image(systemName: "number")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 28, height: 28)
                        .background(Theme.field.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("插入标签")
                .help("插入标签")
            }

            Button { showImagePicker = true } label: {
                Label("图片", systemImage: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Capsule().fill(Theme.field.opacity(0.55)))
            }
            .buttonStyle(.plain)

            if !isQuickCapture {
                HStack(spacing: 5) {
                    Image(systemName: "number")
                        .font(.system(size: 9.5))
                    Text("正文里写 #标签，会自动归类")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            Text("\(text.count) 字")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(Theme.inkFaint)
                .monospacedDigit()

            Text("⌘↩")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkGhost)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.field.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            if !isQuickCapture {
                Button(action: close) {
                    Text("取消")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
            }

            Button { save() } label: {
                HStack(spacing: 5) {
                    Image(systemName: isQuickCapture ? "paperplane.fill" : "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(editingMemo == nil ? "记下" : "完成")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 30)
                .background(
                    Capsule().fill(canSave ? (hoveringSave ? Theme.accentDeep : Theme.accent) : Theme.inkGhost)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: .command)
            .onHover { hoveringSave = $0 }
            .animation(.easeOut(duration: 0.12), value: hoveringSave)
        }
        .padding(.horizontal, isQuickCapture ? 16 : 22)
        .frame(height: 54)
        .background(Theme.bg.opacity(0.95))
    }

    // MARK: 动作

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let memo = editingMemo {
            text = memo.text
            images = memo.imageDatas
        } else {
            text = request.seedText
        }
        selection = NSRange(location: text.utf16.count, length: 0)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            memoEditor.focus()
        }
    }

    private func insertTag(_ tag: String) {
        if let completion = activeCompletion {
            var range = completion.range
            let end = NSMaxRange(range)
            let source = text as NSString
            if end == source.length {
                memoEditor.replace(range, with: "#\(tag) ")
            } else if source.character(at: end) == 32 {
                range.length += 1
                memoEditor.replace(range, with: "#\(tag) ")
            } else {
                memoEditor.replace(range, with: "#\(tag)")
            }
        } else {
            let separator = text.last?.isWhitespace == false ? " " : ""
            memoEditor.replace(NSRange(location: text.utf16.count, length: 0), with: "\(separator)#\(tag) ")
        }
    }

    private func beginTag() {
        if completion != nil {
            suppressedCompletion = nil
            memoEditor.focus()
            return
        }
        let caret = selection.flatMap { range in
            Range(range, in: text)?.upperBound.samePosition(in: text)
        } ?? text.endIndex
        let previous = caret > text.startIndex ? text[text.index(before: caret)] : nil
        let separator = previous.map { !TagParser.isBoundary($0) } == true ? " " : ""
        suppressedCompletion = nil
        memoEditor.replace(NSRange(caret..<caret, in: text), with: separator + "#")
    }

    private func close() {
        if let quickCapture {
            quickCapture.hide()
        } else {
            dismiss()
        }
    }

    private func handleEscape() {
        if let activeCompletion {
            suppressedCompletion = activeCompletion
        } else {
            close()
        }
    }

    private func handleSuggestionKey(_ key: MemoTextEditor.SuggestionKey) -> Bool {
        guard let activeCompletion else { return false }
        if case .dismiss = key {
            suppressedCompletion = activeCompletion
            return true
        }

        let tags = matches(for: activeCompletion)
        guard !tags.isEmpty else { return false }
        let index = min(selectedTagIndex, tags.count - 1)
        switch key {
        case .previous: selectedTagIndex = max(0, index - 1)
        case .next: selectedTagIndex = min(tags.count - 1, index + 1)
        case .accept: insertTag(tags[index])
        case .dismiss: break
        }
        return true
    }

    private func save() {
        guard canSave else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = editingMemo
        let memo = existing ?? Memo(text: trimmed, imageDatas: images)
        if existing != nil {
            memo.text = trimmed
            memo.imageDatas = images
            memo.updatedAt = .now
        } else {
            context.insert(memo)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            saveError = "记录未能保存，请重试。"
            return
        }

        if isQuickCapture {
            text = ""
            images = []
            selection = nil
            saveError = nil
            memoEditor.view?.undoManager?.removeAllActions()
        } else {
            if existing == nil {
                app.openMemo(memo.id)
            } else {
                app.selectedMemoID = memo.id
            }
            app.showToast(existing == nil ? "记下了" : "已保存")
        }
        close()
    }
}
