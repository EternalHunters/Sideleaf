import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ArticleBrowserView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Article.updatedAt, order: .reverse) private var articles: [Article]

    var body: some View {
        WorkspaceList(
            title: "文章", count: articles.count,
            emptyMessage: "还没有文章", createAction: (label: "新建文章", run: create)
        ) {
            EmptyView()
        } rows: {
            ForEach(articles, id: \.id) { article in
                let selected = app.selectedArticleID == article.id
                WorkspaceRow(selected: selected) {
                    Button { app.selectedArticleID = article.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(article.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            Text("更新于 \(DateText.stamp(article.updatedAt))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func create() {
        do {
            app.selectedArticleID = try Article.create(in: context).id
        } catch {
            app.showToast("文章未能新建", icon: "exclamationmark.circle")
        }
    }
}

struct ArticleDetailView: View {
    @Environment(AppState.self) private var app
    @Query private var articles: [Article]

    var body: some View {
        if let article = articles.first(where: { $0.id == app.selectedArticleID }) {
            ArticleEditorView(article: article)
                .id(article.id)
        } else {
            WorkspaceEmptyState(title: "选择或新建一篇文章", icon: "doc.text")
        }
    }
}

private struct ArticleEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @FocusState private var titleFocused: Bool
    private let article: Article
    @State private var title: String
    @State private var markdown: String
    @State private var preview: String
    @State private var mode: Mode = .split
    @State private var editor = MarkdownSourceEditor.Editor()
    @State private var saveFailed = false
    @State private var confirmingDeletion = false
    @State private var deleted = false

    private enum Mode: String, CaseIterable {
        case source = "源码"
        case split = "分栏"
        case preview = "预览"
    }

    init(article: Article) {
        self.article = article
        _title = State(initialValue: article.title)
        _markdown = State(initialValue: article.markdown)
        _preview = State(initialValue: article.markdown)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if mode != .preview {
                toolbar
            }

            Divider()

            HStack(spacing: 0) {
                if mode != .preview {
                    MarkdownSourceEditor(text: $markdown, editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cardRaised)
                }
                if mode == .split { Divider() }
                if mode != .source {
                    if preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Markdown 预览")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.card)
                    } else {
                        MarkdownPreview(markdown: preview)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if title.isEmpty && markdown.isEmpty { titleFocused = true }
        }
        .task(id: title) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            persist()
        }
        .task(id: markdown) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            preview = markdown
            persist()
        }
        .onDisappear { persist(reportFailure: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persist()
        }
        .alert("删除这篇文章？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: delete)
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("文章标题", text: $title, prompt: Text("未命名文章"))
                .textFieldStyle(.plain)
                .font(Theme.detailTitle)
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .onSubmit {
                    if mode == .preview { mode = .split }
                    Task { @MainActor in
                        guard let view = editor.view else { return }
                        view.window?.makeFirstResponder(view)
                    }
                }

            HStack(spacing: 12) {
                if saveFailed {
                    Button("保存失败，重试") { persist() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.danger)
                } else {
                    Label(hasChanges ? "正在保存" : "已保存", systemImage: hasChanges ? "clock" : "checkmark.circle")
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer()

                Picker("文章显示方式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Menu {
                    Button("导出 Markdown…", action: exportMarkdown)
                    Divider()
                    Button("删除文章", role: .destructive) { confirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("文章操作")
            }
            .font(Theme.caption)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            formatButton(.heading)
            formatButton(.bold, shortcut: "⌘B")
            formatButton(.italic, shortcut: "⌘I")
            formatButton(.link, shortcut: "⌘K")

            Divider().frame(height: 15).padding(.horizontal, 4)

            formatButton(.bulletList)
            formatButton(.checklist)
            formatButton(.quote)
            formatButton(.codeBlock)

            Menu {
                ForEach(MarkdownInsertion.allCases, id: \.self) { item in
                    Button { editor.insert(item) } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                Label("插入", systemImage: "plus")
                    .font(Theme.captionMedium)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("在正文空行输入 / 可打开插入菜单")

            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(Theme.card.opacity(0.7))
    }

    private func formatButton(_ item: MarkdownInsertion, shortcut: String? = nil) -> some View {
        Button { editor.insert(item) } label: {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 27, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.rawValue)
        .help(shortcut.map { "\(item.rawValue) \($0)" } ?? item.rawValue)
    }

    private var hasChanges: Bool { article.title != title || article.markdown != markdown }

    private func persist(reportFailure: Bool = false) {
        guard !deleted, hasChanges else { return }
        let previousTitle = article.title
        let previousMarkdown = article.markdown
        let previousUpdate = article.updatedAt
        article.title = title
        article.markdown = markdown
        article.updatedAt = .now
        do {
            try context.save()
            saveFailed = false
        } catch {
            article.title = previousTitle
            article.markdown = previousMarkdown
            article.updatedAt = previousUpdate
            saveFailed = true
            if reportFailure {
                app.showToast("文章改动未能保存", icon: "exclamationmark.circle")
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = name.isEmpty ? article.displayTitle : name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = filename + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = name.isEmpty ? markdown : "# \(name)\n\n\(markdown)"
            try content.write(to: url, atomically: true, encoding: .utf8)
            app.showToast("已导出 Markdown", icon: "square.and.arrow.up")
        } catch {
            app.showToast("Markdown 文件未能导出", icon: "exclamationmark.circle")
        }
    }

    private func delete() {
        context.delete(article)
        do {
            try context.save()
            deleted = true
            app.selectedArticleID = nil
            app.showToast("已删除文章", icon: "trash")
        } catch {
            context.rollback()
            app.showToast("文章未能删除", icon: "exclamationmark.circle")
        }
    }
}
