import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \DailyReview.day, order: .reverse) private var reviews: [DailyReview]
    @State private var captureHovered = false

    private var roots: [TagNode] { TagParser.roots(for: memos) }

    private var flatTags: [(node: TagNode, depth: Int)] {
        var out: [(TagNode, Int)] = []
        func walk(_ nodes: [TagNode], depth: Int) {
            for node in nodes {
                out.append((node, depth))
                if app.expandedTags.contains(node.path) {
                    walk(node.sortedChildren, depth: depth + 1)
                }
            }
        }
        walk(roots, depth: 0)
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            brand
            captureCard
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    navigationRows
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            footer
        }
        .background(
            ZStack {
                Theme.sidebar
                LinearGradient(
                    colors: [Color.white.opacity(0.34), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.hairline.opacity(0.8))
                .frame(width: 0.8)
                .ignoresSafeArea()
        }
    }

    // MARK: 品牌

    private var brand: some View {
        HStack(spacing: 10) {
            FlomoMark(size: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppBrand.name)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .tracking(-0.4)
                Text("把想法留在这里")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.inkFaint)
                    .tracking(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 38)
        .padding(.bottom, 18)
    }

    private var captureCard: some View {
        Button { app.compose() } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(captureHovered ? Theme.accent : Theme.accent.opacity(0.92))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("记一笔")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("此刻在想什么")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: 4)
                Text("⌘N")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(captureHovered ? Theme.card : Theme.card.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(captureHovered ? Theme.accent.opacity(0.22) : Theme.hairlineSoft, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(captureHovered ? 0.055 : 0.02), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { captureHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: captureHovered)
    }

    // MARK: 主导航

    private var navigationRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("浏览")

            navRow(.all, title: "全部记录", icon: "text.alignleft", count: memos.count)
            navRow(.review, title: "每日回顾", icon: "clock.arrow.circlepath", count: nil)
            navRow(.insights, title: "回望", icon: "sparkles", count: nil)

            sectionLabel("写作与计划")
                .padding(.top, 16)

            navRow(.articles, title: SidebarSelection.articles.title, icon: "doc.text", count: nil)
            navRow(.todos, title: SidebarSelection.todos.title, icon: "checklist", count: nil)

            sectionLabel("标签")
                .padding(.top, 16)

            if flatTags.isEmpty {
                Text("在正文里写 #标签\n它就会长在这里")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
                    .lineSpacing(3)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
            } else {
                ForEach(flatTags, id: \.node.path) { item in
                    tagRow(item.node, depth: item.depth)
                }
            }
        }
    }

    private func navRow(_ target: SidebarSelection, title: String, icon: String, count: Int?) -> some View {
        let selected = app.selection == target
        return Button { app.select(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSoft)
                    .frame(width: 17)
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(selected ? Theme.accent.opacity(0.8) : Theme.inkFaint)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.card.opacity(0.9) : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 2.5, height: 16)
                        .padding(.leading, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tagRow(_ node: TagNode, depth: Int) -> some View {
        let selected = app.selection == .tag(node.path)
        let open = app.expandedTags.contains(node.path)
        let hasChildren = !node.sortedChildren.isEmpty

        return HStack(spacing: 1) {
            if hasChildren {
                Button {
                    if open {
                        app.expandedTags.remove(node.path)
                    } else {
                        app.expandedTags.insert(node.path)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 15, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 15, height: 28)
            }

            Button { app.select(.tag(node.path)) } label: {
                HStack(spacing: 5) {
                    if depth == 0 {
                        Text("#")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? Theme.accent : Theme.tag.opacity(0.5))
                    } else {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(width: 7, height: 1)
                    }
                    Text(node.name)
                        .font(.system(size: depth == 0 ? 13 : 12.5, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Theme.ink : (depth == 0 ? Theme.inkSoft : Theme.inkFaint))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(node.count)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.inkFaint.opacity(0.85))
                        .monospacedDigit()
                }
                .padding(.trailing, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Theme.accentSoft : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 14 + 2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.inkFaint)
            .tracking(1.1)
            .padding(.horizontal, 11)
            .padding(.top, 4)
            .padding(.bottom, 5)
    }

    // MARK: 底部

    private var footer: some View {
        let streak = ReviewPlanner.streak(in: reviews)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.7)

            HStack(spacing: 9) {
                if streak > 0 {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text("连续回顾 \(streak) 天")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Image(systemName: "leaf")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text("本地优先 · 安静记录")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 4)
                Button {
                    app.select(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(app.selection == .settings ? Theme.accent : Theme.inkFaint)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(app.selection == .settings ? Theme.accentSoft : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 16)
            .frame(height: 45)
        }
        .background(Theme.sidebar.opacity(0.9))
    }
}
