import SwiftUI
import SwiftData
import AppKit

struct MemoBrowserView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \DailyReview.day, order: .reverse) private var reviews: [DailyReview]

    @FocusState private var searchFocused: Bool
    @State private var appeared = false

    private var filtered: [Memo] {
        let base: [Memo]
        switch app.selection {
        case .pinned:
            base = memos.filter(\.isPinned)
        case .tag(let path):
            base = memos.filter { memo in
                memo.tags.contains { $0 == path || $0.hasPrefix(path + "/") }
            }
        default:
            base = memos
        }

        let query = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }

        if query.hasPrefix("#") {
            let tag = String(query.dropFirst()).lowercased()
            guard !tag.isEmpty else { return [] }
            return base.filter { memo in
                memo.tags.contains { $0.lowercased().contains(tag) }
            }
        }
        return base.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var sections: [MemoSection] {
        let searching = !app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if case .pinned = app.selection {
            return [MemoSection(id: "pinned", title: "置顶", subtitle: "\(filtered.count) 条", memos: filtered)]
        }

        var result: [MemoSection] = []
        if app.selection == .all && !searching {
            let pinned = filtered.filter(\.isPinned)
            if !pinned.isEmpty {
                result.append(MemoSection(id: "pinned", title: "置顶", subtitle: "\(pinned.count) 条", memos: pinned))
            }
        }

        let active = (app.selection == .all && !searching) ? filtered.filter { !$0.isPinned } : filtered
        let grouped = Dictionary(grouping: active) { DateText.startOfDay($0.createdAt) }
        for day in grouped.keys.sorted(by: >) {
            let items = (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            result.append(MemoSection(
                id: "day-\(day.timeIntervalSince1970)",
                title: DateText.dayHeader(day),
                subtitle: "\(items.count) 条",
                memos: items
            ))
        }
        return result
    }

    private var title: String {
        switch app.selection {
        case .all: return "全部记录"
        case .pinned: return "置顶"
        case .tag(let path): return "#" + path
        default: return app.selection.title
        }
    }

    private var subtitle: String {
        let query = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return filtered.isEmpty ? "没有找到匹配的记录" : "找到 \(filtered.count) 条"
        }
        if case .tag(let path) = app.selection {
            let children = Set(memos.flatMap(\.tags).filter { $0.hasPrefix(path + "/") }).count
            return children > 0 ? "\(filtered.count) 条 · 含 \(children) 个子标签" : "\(filtered.count) 条记录"
        }
        let today = memos.filter { DateText.cal.isDateInToday($0.createdAt) }.count
        if case .pinned = app.selection {
            return filtered.isEmpty ? "还没有置顶的记录" : "\(filtered.count) 条被留在了最上面"
        }
        return "今天 \(today) 条 · 共 \(memos.count) 条"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Rectangle()
                .fill(Theme.hairlineSoft)
                .frame(height: 0.7)

            if sections.isEmpty {
                emptyState
            } else {
                memoScroll
            }
        }
        .onAppear {
            appeared = true
            ensureSelection()
        }
        .onChange(of: app.selection) { _, _ in
            ensureSelection()
            if !app.searchText.isEmpty {
                app.searchText = ""
            }
        }
        .onChange(of: app.searchText) { _, _ in ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: app.searchFocusRequest) { _, _ in
            Task { @MainActor in searchFocused = true }
        }
        .background(Theme.bg)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 12)
            Button { app.compose() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
            .help("新建记录 ⌘N")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.inkFaint)

            TextField("搜索笔记，或输入 #标签", text: Binding(
                get: { app.searchText },
                set: { app.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .focused($searchFocused)

            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            } else {
                Text("⇧⌘F")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkGhost)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(searchFocused ? Theme.card : Theme.field.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(searchFocused ? Theme.accent.opacity(0.35) : .clear, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .animation(.easeOut(duration: 0.13), value: searchFocused)
    }

    // MARK: 列表

    private var memoScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.memos) { memo in
                            MemoRowView(memo: memo, selected: app.selectedMemoID == memo.id)
                                .padding(.horizontal, 10)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
                Color.clear.frame(height: 26)
            }
        }
    }

    private func sectionHeader(_ section: MemoSection) -> some View {
        HStack(spacing: 7) {
            if section.id == "pinned" {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(12))
            }
            Text(section.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(section.subtitle)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.inkFaint)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, section.id == "pinned" ? 8 : 15)
        .padding(.bottom, 7)
        .background(
            Theme.bg.opacity(0.97)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairlineSoft.opacity(0.55)).frame(height: 0.5)
                }
        )
    }

    private var emptyState: some View {
        let searching = !app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: searching ? "magnifyingglass" : (app.selection == .pinned ? "pin" : "square.and.pencil"))
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Theme.inkGhost)
            Text(searching ? "没有找到" : emptyTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            Text(searching ? "换个更短的关键词，或者试试 #标签" : emptyHint)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if !searching && app.selection == .all {
                Button { app.compose() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("写下第一条")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    private var emptyTitle: String {
        switch app.selection {
        case .pinned: return "还没有置顶"
        case .tag: return "这个标签下还没有内容"
        default: return "这一页还空着"
        }
    }

    private var emptyHint: String {
        switch app.selection {
        case .pinned: return "在任意记录上右键，就可以把它留在最上面。"
        case .tag: return "在正文里写这个标签，记录就会自动归到这里。"
        default: return "不用完整，不用正确。\n先把脑子里那一句放下来。"
        }
    }

    private func ensureSelection() {
        guard !filtered.isEmpty else {
            app.selectedMemoID = nil
            return
        }
        if let id = app.selectedMemoID, filtered.contains(where: { $0.id == id }) { return }
        app.selectedMemoID = filtered.first?.id
    }
}

struct MemoSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let memos: [Memo]
}

struct MemoRowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    let memo: Memo
    let selected: Bool

    @State private var hovering = false

    private var background: Color {
        if selected { return Theme.accentSoft.opacity(0.82) }
        if hovering { return Theme.card.opacity(0.72) }
        return .clear
    }

    var body: some View {
        Button {
            app.selectedMemoID = memo.id
        } label: {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(selected ? Theme.accent : .clear)
                    .frame(width: 2.5, height: selected ? 30 : 0)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Text(DateText.clock(memo.createdAt))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(selected ? Theme.accent.opacity(0.9) : Theme.inkFaint)
                            .monospacedDigit()

                        if memo.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7.5))
                                .foregroundStyle(Theme.accent.opacity(0.7))
                                .rotationEffect(.degrees(12))
                        }

                        Spacer(minLength: 4)

                        if !memo.imageDatas.isEmpty {
                            Image(systemName: "photo")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.inkFaint)
                            Text("\(memo.imageDatas.count)")
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }

                    Text(TagParser.highlight(memo.text, color: selected ? Theme.accentDeep : Theme.tag))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink.opacity(selected ? 1 : 0.88))
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if !memo.imageDatas.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(memo.imageDatas.prefix(3).enumerated()), id: \.offset) { _, data in
                                if let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                            }
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contextMenu {
            Button {
                app.edit(memoID: memo.id)
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button {
                memo.isPinned.toggle()
                memo.updatedAt = .now
                try? context.save()
                app.showToast(memo.isPinned ? "已置顶" : "已取消置顶", icon: "pin")
            } label: {
                Label(memo.isPinned ? "取消置顶" : "置顶", systemImage: memo.isPinned ? "pin.slash" : "pin")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.text, forType: .string)
                app.showToast("已复制正文", icon: "doc.on.doc")
            } label: {
                Label("复制正文", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                app.pendingDeleteID = memo.id
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
