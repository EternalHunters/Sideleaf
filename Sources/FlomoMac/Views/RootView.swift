import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var allMemos: [Memo]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var reviewVisibility: NavigationSplitViewVisibility = .all

    private var composerBinding: Binding<ComposerRequest?> {
        Binding(
            get: { app.composerRequest },
            set: { app.composerRequest = $0 }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { app.pendingDeleteID != nil },
            set: { if !$0 { app.pendingDeleteID = nil } }
        )
    }

    var body: some View {
        navigation
        .navigationSplitViewStyle(.balanced)
        .background(PaperBackdrop())
        .sheet(item: composerBinding) { request in
            ComposerView(request: request)
                .environment(app)
        }
        .alert("删除这条记录？", isPresented: deleteBinding) {
            Button("删除", role: .destructive) { deleteRequestedMemo() }
            Button("取消", role: .cancel) { app.pendingDeleteID = nil }
        } message: {
            Text("删掉之后就找不回来了。")
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.toast?.id)
        .onOpenURL { handle($0) }
    }

    @ViewBuilder
    private var navigation: some View {
        if app.selection == .review {
            NavigationSplitView(columnVisibility: $reviewVisibility) {
                sidebar
            } detail: {
                ReviewDeckView()
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } content: {
                BrowserColumn()
                    .navigationSplitViewColumnWidth(min: 326, ideal: 356, max: 440)
            } detail: {
                DetailColumn()
            }
        }
    }

    private var sidebar: some View {
        SidebarView()
            .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 254)
    }

    /// 从浏览器、快捷指令或终端把应用带到某个位置。
    /// sideleaf://new · sideleaf://review · sideleaf://insights · sideleaf://settings/data
    /// sideleaf://tag/读书 · sideleaf://memo/<uuid>
    private func handle(_ url: URL) {
        guard AppBrand.acceptsURLScheme(url.scheme) else { return }
        let host = (url.host ?? "").lowercased()

        switch host {
        case "new", "compose":
            app.compose()
        case "review":
            app.select(.review)
        case "insights", "lookback":
            app.select(.insights)
        case "settings":
            app.select(.settings)
            let section = url.pathComponents.dropFirst().first ?? ""
            app.settingsSection = SettingsSection(rawValue: section) ?? .general
        case "tag":
            let tag = url.pathComponents.dropFirst().joined(separator: "/")
                .removingPercentEncoding ?? ""
            if !tag.isEmpty { app.select(.tag(tag)) }
        case "memo":
            guard let id = MarkdownHTML.memoLinkID(url) else { return }
            guard allMemos.contains(where: { $0.id == id }) else {
                app.showToast("找不到原记录", icon: "exclamationmark.circle")
                return
            }
            app.openMemo(id)
        default:
            if url.pathComponents.count > 1 {
                app.select(.all)
            }
        }
    }

    private func deleteRequestedMemo() {
        guard let id = app.pendingDeleteID else { return }
        if let memo = allMemos.first(where: { $0.id == id }) {
            context.delete(memo)
            try? context.save()
            if app.selectedMemoID == id { app.selectedMemoID = nil }
            app.showToast("已删除", icon: "trash")
        }
        app.pendingDeleteID = nil
    }
}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: toast.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 6)
    }
}
