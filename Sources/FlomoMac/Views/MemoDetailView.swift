import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct MemoDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]

    @State private var editing = false
    @State private var draft = ""
    @State private var draftImages: [Data] = []
    @State private var editingMemoID: UUID?
    @State private var originalText = ""
    @State private var originalImages: [Data] = []
    @State private var autosaveTask: Task<Void, Never>?
    @State private var preview: ImagePreviewPayload?
    @State private var showImagePicker = false
    @State private var hoveringRelated: UUID?

    @FocusState private var editorFocused: Bool

    private var memo: Memo? {
        guard let id = app.selectedMemoID else { return nil }
        return memos.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let memo {
                content(memo)
                    .id(memo.id)
            } else {
                EmptyDetailView()
            }
        }
        .onChange(of: app.selectedMemoID) { oldID, newID in
            saveIfNeeded(oldID: oldID)
            editing = false
            editingMemoID = nil
            draft = memo?.text ?? ""
            draftImages = memo?.imageDatas ?? []
            if newID == nil { app.selectedMemoID = nil }
        }
        .onAppear {
            draft = memo?.text ?? ""
            draftImages = memo?.imageDatas ?? []
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .onChange(of: draftImages) { _, _ in scheduleAutosave() }
        .onDisappear { persistDraftNow() }
        .sheet(item: $preview) { payload in
            ImagePreviewSheet(payload: payload)
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if let data = ImageTools.readSecurityScoped(url) {
                        draftImages.append(ImageTools.compress(data))
                    }
                }
            }
        }
    }

    private func content(_ memo: Memo) -> some View {
        VStack(spacing: 0) {
            toolbar(memo)
            Rectangle()
                .fill(Theme.hairlineSoft)
                .frame(height: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    dateHeading(memo)

                    if editing {
                        editor
                    } else {
                        reader(memo)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 54)
                .padding(.top, 38)
                .padding(.bottom, 70)
            }
        }
    }

    // MARK: 顶栏

    private func toolbar(_ memo: Memo) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: memo.isPinned ? "pin.fill" : "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(memo.isPinned ? Theme.accent : Theme.inkFaint)
                    .rotationEffect(.degrees(memo.isPinned ? 12 : 0))
                Text(memo.isPinned ? "置顶记录" : "记录")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                Text("·")
                    .foregroundStyle(Theme.inkGhost)
                Text(DateText.stamp(memo.createdAt))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            if editing {
                Text("自动保存在本机")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.trailing, 4)

                Button("取消") { cancelEditing() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])

                Button("完成") { finishEditing(memo) }
                    .buttonStyle(PrimarySmallButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                DetailIconButton(icon: "photo.on.rectangle", help: "添加图片") {
                    draft = memo.text
                    draftImages = memo.imageDatas
                    editing = true
                    editingMemoID = memo.id
                    showImagePicker = true
                }

                DetailIconButton(
                    icon: memo.isPinned ? "pin.fill" : "pin",
                    help: memo.isPinned ? "取消置顶" : "置顶",
                    active: memo.isPinned
                ) {
                    memo.isPinned.toggle()
                    memo.updatedAt = .now
                    try? context.save()
                    app.showToast(memo.isPinned ? "已置顶" : "已取消置顶", icon: "pin")
                }

                DetailIconButton(icon: "doc.on.doc", help: "复制正文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(memo.text, forType: .string)
                    app.showToast("已复制正文", icon: "doc.on.doc")
                }

                DetailIconButton(icon: "pencil", help: "编辑 ⌘E") {
                    beginEditing(memo)
                }

                Menu {
                    Button {
                        beginEditing(memo)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        app.compose(seedText: memo.text)
                    } label: {
                        Label("复制为新记录", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.pendingDeleteID = memo.id
                    } label: {
                        Label("删除这条记录", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.field.opacity(0.65)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Theme.bg.opacity(0.72))
    }

    // MARK: 日期

    private func dateHeading(_ memo: Memo) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(DateText.dayKicker(memo.createdAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .tracking(0.6)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(DateText.dayNumber(memo.createdAt))
                        .font(.system(size: 44, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text(DateText.monthName(memo.createdAt))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            Text(DateText.clock(memo.createdAt))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkFaint)
                .monospacedDigit()
                .padding(.bottom, 5)
        }
        .padding(.bottom, 26)
    }

    // MARK: 阅读

    private func reader(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if memo.text.isEmpty {
                Text("（这条记录只有图片）")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkFaint)
                    .italic()
            } else {
                Text(TagParser.highlight(memo.text))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.ink.opacity(0.94))
                    .lineSpacing(10)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !memo.imageDatas.isEmpty {
                imageGrid(memo.imageDatas)
                    .padding(.top, 24)
            }

            if !memo.tags.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(Array(memo.tags.enumerated()), id: \.offset) { _, tag in
                        Button {
                            app.select(.tag(tag))
                        } label: {
                            Text("#" + tag)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.tag)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Theme.accentSoft.opacity(0.8))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 26)
            }

            Rectangle()
                .fill(Theme.hairlineSoft)
                .frame(height: 1)
                .padding(.top, 32)

            relatedSection(memo)
                .padding(.top, 22)

            HStack(spacing: 8) {
                Text("写于 \(DateText.absolute(memo.createdAt))")
                if memo.updatedAt.timeIntervalSince(memo.createdAt) > 60 {
                    Text("· 最后编辑 \(DateText.stamp(memo.updatedAt))")
                }
                Spacer()
                Text("\(memo.text.count) 字")
                    .monospacedDigit()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.inkGhost)
            .padding(.top, 20)
        }
    }

    private func imageGrid(_ images: [Data]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.black.opacity(0.045), lineWidth: 0.7)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            preview = ImagePreviewPayload(data: data)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func relatedSection(_ memo: Memo) -> some View {
        let related = memos.filter { other in
            other.id != memo.id && !Set(other.tags).isDisjoint(with: Set(memo.tags))
        }.prefix(3)

        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text("同一条线索")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text("\(related.count) 条")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }

                ForEach(Array(related)) { other in
                    Button {
                        app.selectedMemoID = other.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(DateText.stamp(other.createdAt))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.inkFaint)
                                .frame(width: 82, alignment: .leading)
                                .padding(.top, 1)
                            Text(TagParser.highlight(other.text))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(2)
                                .lineSpacing(3)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.inkGhost)
                                .padding(.top, 3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(hoveringRelated == other.id ? Theme.card : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveringRelated = $0 ? other.id : nil }
                }
            }
        }
    }

    // MARK: 编辑

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("此刻在想什么…")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.inkGhost)
                        .padding(.top, 3)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(9)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .focused($editorFocused)
                    .frame(minHeight: 320)
                    .padding(.horizontal, -5)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card.opacity(0.68))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(0.16), lineWidth: 1)
            )

            if !draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(Array(draftImages.enumerated()), id: \.offset) { index, data in
                            if let image = NSImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 82, height: 82)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Button {
                                        draftImages.remove(at: index)
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
                                    .font(.system(size: 14, weight: .medium))
                                Text("图片")
                                    .font(.system(size: 9.5))
                            }
                            .foregroundStyle(Theme.inkFaint)
                            .frame(width: 82, height: 82)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(Theme.hairline)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 14) {
                Button { showImagePicker = true } label: {
                    Label("图片", systemImage: "photo")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)

                Label("支持 #标签", systemImage: "number")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)

                Spacer()

                Text("\(draft.count) 字")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
                    .monospacedDigit()

                Text("⌘↩ 完成")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkGhost)
            }
        }
    }

    private func beginEditing(_ memo: Memo) {
        autosaveTask?.cancel()
        originalText = memo.text
        originalImages = memo.imageDatas
        draft = memo.text
        draftImages = memo.imageDatas
        editingMemoID = memo.id
        editing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            editorFocused = true
        }
    }

    private func finishEditing(_ memo: Memo) {
        autosaveTask?.cancel()
        memo.text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        memo.imageDatas = draftImages
        memo.updatedAt = .now
        try? context.save()
        editing = false
        editingMemoID = nil
        app.showToast("已保存")
    }

    private func cancelEditing() {
        autosaveTask?.cancel()
        editing = false
        if let id = editingMemoID, let old = memos.first(where: { $0.id == id }) {
            old.text = originalText
            old.imageDatas = originalImages
            try? context.save()
        }
        draft = originalText
        draftImages = originalImages
        editingMemoID = nil
        editorFocused = false
    }

    private func scheduleAutosave() {
        guard editing, let id = editingMemoID else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, editing, editingMemoID == id,
                  let memo = memos.first(where: { $0.id == id }) else { return }
            memo.text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            memo.imageDatas = draftImages
            memo.updatedAt = .now
            try? context.save()
        }
    }

    private func persistDraftNow() {
        guard editing, let id = editingMemoID,
              let memo = memos.first(where: { $0.id == id }) else { return }
        autosaveTask?.cancel()
        memo.text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        memo.imageDatas = draftImages
        memo.updatedAt = .now
        try? context.save()
    }

    private func saveIfNeeded(oldID: UUID?) {
        guard editing, let id = editingMemoID, id == oldID else { return }
        persistDraftNow()
        editing = false
        editingMemoID = nil
    }
}

// MARK: - 空态

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.hairline.opacity(0.9), lineWidth: 1)
                    .frame(width: 122, height: 122)
                    .rotationEffect(.degrees(8))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(10), spacing: 9), count: 4),
                    spacing: 9
                ) {
                    ForEach(0..<16, id: \.self) { index in
                        Circle()
                            .fill(index == 10 ? Theme.accent : Theme.inkGhost.opacity(0.55))
                            .frame(
                                width: index == 10 ? 12 : 8,
                                height: index == 10 ? 12 : 8
                            )
                    }
                }
            }
            .padding(.bottom, 30)

            Text("把想法留在这里")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)

            Text("不必完整，不必正确。\n先让它在纸上落下来。")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            HStack(spacing: 18) {
                shortcutHint(keys: "⌘N", label: "新记录")
                Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
                shortcutHint(keys: "⇧⌘F", label: "搜索")
                Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
                shortcutHint(keys: "⌘E", label: "编辑")
            }
            .padding(.top, 27)

            Spacer()
            Text("所有内容只保存在这台 Mac 上")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkGhost)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutHint(keys: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Theme.hairlineSoft, lineWidth: 0.7)
                )
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}

// MARK: - 小组件

struct DetailIconButton: View {
    let icon: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(active ? Theme.accent : (hovering ? Theme.ink : Theme.inkSoft))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(active ? Theme.accentSoft : (hovering ? Theme.field : Theme.field.opacity(0.55)))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct PrimarySmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 29)
            .background(
                Capsule().fill(configuration.isPressed ? Theme.accentDeep : Theme.accent)
            )
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.inkSoft)
            .padding(.horizontal, 11)
            .frame(height: 29)
            .background(
                Capsule().fill(Theme.field.opacity(configuration.isPressed ? 1 : 0.55))
            )
    }
}

struct ImagePreviewPayload: Identifiable {
    let id = UUID()
    let data: Data
}

struct ImagePreviewSheet: View {
    let payload: ImagePreviewPayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("图片")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.field))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(14)

            if let image = NSImage(data: payload.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 880, maxHeight: 620)
                    .padding(18)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(Theme.bg)
    }
}
