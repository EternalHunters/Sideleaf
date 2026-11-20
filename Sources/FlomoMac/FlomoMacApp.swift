import SwiftUI
import SwiftData

@main
struct FlomoMacApp: App {
    let container: ModelContainer
    @NSApplicationDelegateAdaptor(QuickCaptureMenu.self) private var quickCapture
    @State private var appState: AppState
    @State private var syncManager: SyncManager
    @State private var aiReview: AIReviewService

    init() {
        let schema = Schema([Memo.self, DailyReview.self, Article.self, TodoItem.self, TodoSubtask.self])
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("flomo-mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appendingPathComponent("flomo.store")
        let config = ModelConfiguration("FlomoMac", schema: schema, url: storeURL)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("本地存储初始化失败：\(error)")
        }

        let state = AppState()
        _appState = State(initialValue: state)
        _syncManager = State(initialValue: SyncManager())
        _aiReview = State(initialValue: AIReviewService(storageDirectory: folder))
        quickCapture.configure(appState: state, container: container)
        SeedData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        Window(AppBrand.name, id: "main") {
            RootView()
                .environment(appState)
                .environment(syncManager)
                .environment(aiReview)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .modelContainer(container)
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appState: appState, showQuickCapture: quickCapture.show)
        }
    }
}

struct AppCommands: Commands {
    let appState: AppState
    let showQuickCapture: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建记录") { appState.compose() }
                .keyboardShortcut("n", modifiers: .command)
            Button("快速记录", action: showQuickCapture)
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                appState.select(.settings)
                appState.settingsSection = .general
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("笔记") {
            Button("编辑当前记录") {
                if let id = appState.selectedMemoID { appState.edit(memoID: id) }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(appState.selectedMemoID == nil)

            Divider()

            Button("搜索笔记") { appState.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("每日回顾") { appState.select(.review) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("全部记录") { appState.select(.all) }
                .keyboardShortcut("1", modifiers: .command)
            Button("置顶") { appState.select(.pinned) }
                .keyboardShortcut("2", modifiers: .command)
            Button("回望") { appState.select(.insights) }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}

enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Memo>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let cal = DateText.cal
        let now = Date()
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let seeds: [(String, Int, Int, Int, Bool)] = [
            ("欢迎使用 \(AppBrand.name)。\n\n按 ⌘N 记一条笔记，在正文输入 # 可以选择标签，也可以从菜单栏打开快速记录。\n\n在「回望」整理笔记，在「文章」继续写下去。 #使用说明", 0, 9, 20, true),
            ("把「记录」和「输出」拆开之后，写东西的心理负担小了很多。\n以前总想着每一条都要能发出去，结果一个字都写不动。 #思考/写作", 0, 8, 42, false),
            ("桌面端最适合做的事，是让信息保持可见，而不是把它塞进更多的弹窗里。 #产品/设计", 1, 21, 10, false),
            ("和做产品的朋友聊了两小时，最有价值的一句是：\n用户不是在买功能，是在买一个更省事的自己。 #产品", 2, 22, 5, false),
            ("重读《纳瓦尔宝典》。「用判断力赚钱」这句依然有冲击。\n大部分人卖的是时间，少数人卖的是判断。 #读书/商业", 4, 23, 18, false),
            ("今天开会又陷入了「要不要加这个功能」的循环。\n真正该问的是：不加会怎样？ #产品/决策", 7, 15, 30, false),
            ("散步时想到：我的笔记越来越像仓库，不像工作台。\n存进去的东西没有被重新看过一次。 #思考", 12, 19, 18, false),
            ("试了三天早上不看手机。变化没有想象中大，但早上多出了四十多分钟。 #习惯", 19, 8, 2, false),
            ("所谓积累，就是把同一件事反复想，想到别人没想到的那一层。 #思考", 37, 20, 15, false),
            ("开始用卡片盒方法。之前的笔记都是死的，因为没有连接。 #方法", 68, 18, 50, false),
            ("重读《金字塔原理》。结论先行这件事，说着简单做着难。 #读书/商业", 126, 21, 25, false),
            ("一年前的今天也在想同一件事，只是当时没想明白。 #思考/复盘", 365, 20, 15, false),
        ]

        for (text, daysAgo, hour, minute, pinned) in seeds {
            let memo = Memo(text: text, createdAt: at(daysAgo, hour, minute))
            memo.isPinned = pinned
            context.insert(memo)
        }

        try? context.save()
    }
}
