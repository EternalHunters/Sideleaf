import Foundation
import Observation

enum SidebarSelection: Hashable {
    case all
    case pinned
    case review
    case articles
    case todos
    case tag(String)
    case insights
    case settings

    var title: String {
        switch self {
        case .all: return "全部记录"
        case .pinned: return "置顶"
        case .review: return "每日回顾"
        case .articles: return "文章"
        case .todos: return "待办"
        case .tag(let path): return "#" + (path.split(separator: "/").last.map(String.init) ?? path)
        case .insights: return "回望"
        case .settings: return "设置"
        }
    }

    var isMemoList: Bool {
        switch self {
        case .all, .pinned, .tag: return true
        default: return false
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case data
    case sync
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "偏好"
        case .data: return "数据与备份"
        case .sync: return "同步"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .data: return "externaldrive"
        case .sync: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "回顾节奏与输入习惯"
        case .data: return "导入、导出与本地数据"
        case .sync: return "连接你自己的同步服务"
        case .about: return "这只桌面版从哪里来"
        }
    }
}

enum InsightRange: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "本周"
        case .month: return "近 30 天"
        case .all: return "全部时间"
        }
    }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }
}

struct ComposerRequest: Identifiable {
    let id = UUID()
    var memoID: UUID?
    var seedText: String = ""
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var icon: String = "checkmark.circle.fill"
}

@MainActor
@Observable
final class AppState {
    var selection: SidebarSelection = .all
    var selectedMemoID: UUID?
    var selectedArticleID: UUID?
    var selectedTodoID: UUID?
    var searchText = ""
    var searchFocusRequest = 0

    var composerRequest: ComposerRequest?
    var expandedTags: Set<String> = []
    var pendingDeleteID: UUID?

    var insightRange: InsightRange = .week
    var settingsSection: SettingsSection = .general

    var toast: ToastMessage?

    /// Cmd+N：新记录
    func compose(seedText: String = "") {
        composerRequest = ComposerRequest(memoID: nil, seedText: seedText)
    }

    /// Cmd+E：编辑当前笔记
    func edit(memoID: UUID) {
        composerRequest = ComposerRequest(memoID: memoID)
    }

    /// Cmd+F：把焦点送回搜索框
    func focusSearch() {
        searchFocusRequest += 1
    }

    func select(_ next: SidebarSelection) {
        guard selection != next else { return }
        selection = next
        if next.isMemoList {
            selectedMemoID = nil
        }
        searchText = ""
    }

    func openMemo(_ id: UUID) {
        select(.all)
        searchText = ""
        selectedMemoID = id
    }

    func showToast(_ text: String, icon: String = "checkmark.circle.fill") {
        toast = ToastMessage(text: text, icon: icon)
        let current = toast?.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast?.id == current { toast = nil }
        }
    }
}
