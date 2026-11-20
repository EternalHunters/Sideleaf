import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsBrowserView: View {
    @Environment(AppState.self) private var app
    @Query private var memos: [Memo]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.ink)
                Text("把这里调成自己的样子")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.hairlineSoft).frame(height: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        row(section)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 9.5))
                            Text("本地优先")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.accent)
                        Text("\(memos.count) 条记录存在这台 Mac 上。\n可以随时导出为 Markdown。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkFaint)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.accentMist.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 22)
            }

            HStack {
                Text(AppBrand.name)
                    .font(.system(size: 9.5, design: .rounded))
                Spacer()
                Text("v1.0.0")
                    .font(.system(size: 9.5, design: .rounded))
            }
            .foregroundStyle(Theme.inkGhost)
            .padding(.horizontal, 20)
            .frame(height: 34)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairlineSoft).frame(height: 0.6)
            }
        }
        .background(Theme.bg)
    }

    private func row(_ section: SettingsSection) -> some View {
        let selected = app.settingsSection == section
        return Button { app.settingsSection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSoft)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                    Text(section.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.accentSoft.opacity(0.85) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情

struct SettingsDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(SyncManager.self) private var sync
    @Environment(AIReviewService.self) private var aiReview
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query private var reviews: [DailyReview]

    @AppStorage("review.quota") private var quota = 5
    @State private var showWipe = false
    @State private var importFile = false
    @State private var dataNote: String?
    @State private var backupBusy = false
    @State private var showTencentDriveBackup = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader

                switch app.settingsSection {
                case .general:
                    generalSection
                case .data:
                    dataSection
                case .sync:
                    syncSection
                case .about:
                    aboutSection
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 54)
            .padding(.top, 40)
            .padding(.bottom, 64)
        }
        .background(PaperBackdrop())
        .alert("清空本地笔记和回顾？", isPresented: $showWipe) {
            Button("清空笔记和回顾", role: .destructive) { wipeMemosAndReviews() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有笔记、每日回顾和 AI 回望结果都会删除。建议先导出 Markdown。")
        }
        .fileImporter(
            isPresented: $importFile,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            importMarkdown(result)
        }
        .sheet(isPresented: $showTencentDriveBackup) {
            TencentDriveBackupView { message in
                dataNote = message
                app.showToast("已上传到腾讯网盘", icon: "icloud.and.arrow.up")
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("SETTINGS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .tracking(2.1)
                Rectangle().fill(Theme.accent.opacity(0.24)).frame(width: 30, height: 1)
            }
            Text(app.settingsSection.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(app.settingsSection.subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: 偏好

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "每日回顾", note: "从不同时间距离里抽几段往事") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("每次抽取")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.ink)
                        Text("改动从下一次回顾开始生效")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        quotaButton(system: "minus", enabled: quota > 2) {
                            quota = max(2, quota - 1)
                        }
                        Text("\(quota) 条")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                            .frame(width: 36)
                        quotaButton(system: "plus", enabled: quota < 10) {
                            quota = min(10, quota + 1)
                        }
                    }
                }
            }

            settingsCard(title: "快捷键", note: "手可以留在键盘上") {
                shortcutRow("⌘ N", "新建记录")
                divider
                shortcutRow("⌘ E", "编辑当前记录")
                divider
                shortcutRow("⇧ ⌘ F", "搜索笔记")
                divider
                shortcutRow("⌘ ,", "打开设置")
                divider
                shortcutRow("⌘ 1 / 2 / 3", "记录 / 置顶 / 回望")
            }

            settingsCard(title: "外观", note: "纸白、墨黑与松绿") {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.bg).frame(width: 22, height: 22).overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                        Circle().fill(Theme.ink).frame(width: 22, height: 22)
                        Circle().fill(Theme.accent).frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("固定浅色主题")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                        Text("深色模式还在等一位耐心的设计师")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                }
            }
        }
    }

    private func quotaButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? Theme.inkSoft : Theme.inkGhost)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.field.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(keys)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.field.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.vertical, 7)
    }

    // MARK: 数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                dataMetric("\(memos.count)", "笔记")
                dataMetric("\(tagCount)", "标签")
                dataMetric("\(imageCount)", "图片")
                dataMetric("\(reviews.filter(\.isCompleted).count)", "读完回顾")
            }

            settingsCard(title: "备份", note: "记录、图片、文章和待办") {
                actionRow(
                    icon: "arrow.down.document",
                    color: Theme.accent,
                    title: "导出备份文件",
                    detail: "JSON",
                    help: "保存一份可以恢复的本地备份"
                ) { exportWorkspaceBackup() }
                .disabled(backupBusy)

                divider

                actionRow(
                    icon: "icloud.and.arrow.up",
                    color: Theme.accent,
                    title: "备份到腾讯网盘",
                    detail: "手动上传",
                    help: "生成备份文件并上传到选定的网盘目录"
                ) { showTencentDriveBackup = true }
                .disabled(backupBusy)

                divider

                actionRow(
                    icon: "arrow.counterclockwise",
                    color: Theme.accent,
                    title: "从备份文件恢复",
                    detail: "保留本机已有内容",
                    help: "选择本地备份文件，或先从网盘下载一份"
                ) { restoreWorkspaceBackup() }
                .disabled(backupBusy)

                divider

                actionRow(
                    icon: "square.and.arrow.up",
                    color: Theme.accent,
                    title: "导出笔记为 Markdown",
                    detail: "\(memos.count) 条",
                    help: "生成一个可读的 .md 文件"
                ) { exportMarkdown() }

                divider

                actionRow(
                    icon: "square.and.arrow.down",
                    color: Theme.accent,
                    title: "导入 Markdown 笔记",
                    detail: "兼容 iPhone 版导出",
                    help: "按 ## 日期 分节读取"
                ) { importFile = true }
            }

            if let dataNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(dataNote)
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.field.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            settingsCard(title: "本地数据", note: "这台 Mac 上的数据库") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SwiftData 数据库")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                        Text(storePath ?? "数据目录由系统管理")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        revealStore()
                    } label: {
                        Text("显示")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                divider

                actionRow(
                    icon: "trash",
                    color: Theme.danger,
                    title: "清空笔记和回顾",
                    detail: "",
                    help: "不可恢复",
                    titleColor: Theme.danger
                ) { showWipe = true }
            }

            Text("笔记会以系统数据库的形式留在这台 Mac 上。同步是可选项，默认不会把任何内容发出去。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
                .lineSpacing(3)
        }
    }

    private func dataMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 0.7)
        )
    }

    // MARK: 同步

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(sync.isConnected ? Theme.accentSoft : Theme.field)
                        .frame(width: 34, height: 34)
                    Image(systemName: sync.isConnected ? "checkmark.icloud.fill" : "icloud.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(sync.isConnected ? Theme.accent : Theme.inkFaint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(sync.isConnected ? "已连接到自己的服务器" : "还没有连接服务器")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(sync.statusLine)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                if sync.isConnected {
                    Button { sync.disconnect() } label: {
                        Text("断开")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(sync.isConnected ? Theme.accentMist.opacity(0.8) : Theme.card.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(sync.isConnected ? Theme.accent.opacity(0.12) : Theme.hairlineSoft, lineWidth: 0.8)
            )

            settingsCard(title: "连接", note: "地址、账号密码只属于你") {
                fieldLabel("服务器地址")
                TextField("https://your-server.example", text: Binding(
                    get: { sync.baseURL },
                    set: { sync.baseURL = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.field.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                fieldLabel("用户名").padding(.top, 11)
                TextField("名字", text: Binding(
                    get: { sync.username },
                    set: { sync.username = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.field.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                fieldLabel("密码").padding(.top, 11)
                SecureField("密码", text: Binding(
                    get: { sync.password },
                    set: { sync.password = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.field.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                fieldLabel("邀请码（注册时可能需要）").padding(.top, 11)
                TextField("没有就留空", text: Binding(
                    get: { sync.signupKey },
                    set: { sync.signupKey = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.field.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack(spacing: 9) {
                    Button {
                        Task { await sync.login() }
                    } label: {
                        Text(sync.isConnected ? "重新登录" : "登录并连接")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(sync.busy)

                    Button {
                        Task { await sync.register() }
                    } label: {
                        Text("注册新账号")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.field.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .disabled(sync.busy)

                    Spacer()
                    if sync.busy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 15)
            }

            settingsCard(title: "手动同步", note: "没有自动上传，只有你按下按钮时才走网络") {
                HStack(spacing: 12) {
                    syncAction(
                        icon: "arrow.up.to.line",
                        title: "上传到服务器",
                        detail: "\(memos.count) 条",
                        enabled: sync.isConnected && !sync.busy
                    ) {
                        Task {
                            if await sync.upload(memos: memos) {
                                app.showToast("上传完成", icon: "arrow.up.to.line")
                            }
                        }
                    }

                    syncAction(
                        icon: "arrow.down.to.line",
                        title: "从服务器同步",
                        detail: sync.statusLine,
                        enabled: sync.isConnected && !sync.busy
                    ) {
                        Task {
                            if await sync.download(context: context) {
                                app.showToast("同步完成", icon: "arrow.down.to.line")
                            }
                        }
                    }
                }
            }

            if let note = sync.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: sync.noteIsError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(sync.noteIsError ? Theme.danger : Theme.accent)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((sync.noteIsError ? Theme.dangerSoft : Theme.accentMist).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text("服务端只保存纯文本，含图片的笔记会留在本机。密码和 token 存在 macOS 钥匙串。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
                .lineSpacing(3)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.inkFaint)
            .padding(.bottom, 5)
    }

    private func syncAction(
        icon: String,
        title: String,
        detail: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? Theme.accent : Theme.inkGhost)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.field.opacity(enabled ? 0.56 : 0.35))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    FlomoMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppBrand.name)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("本地优先的桌面笔记工作台 · v1.0.0")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }

                Text("随手记录想法，用标签整理笔记，在每日回顾里重读旧记录，也可以把素材写成 Markdown 文章。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Theme.hairlineSoft).frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    principle(icon: "lock", title: "默认不出门", text: "所有笔记都存在这台 Mac 上，不登录也能完整使用。")
                    principle(icon: "text.alignleft", title: "正文就是数据", text: "标签长在文字里，不额外维护一张会失真的表。")
                    principle(icon: "clock.arrow.circlepath", title: "旧东西值得回来", text: "每日回顾按时间距离分层抽取，不只让你重看这一周。")
                    principle(icon: "square.and.arrow.up", title: "随时能带走", text: "一条命令都不需要，直接导出为可读的 Markdown。")
                }
            }
            .padding(18)
            .flomoCard()

        }
    }

    private func principle(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 17)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkFaint)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 通用组件

    private func settingsCard<Content: View>(
        title: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.inkFaint)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.card.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.018), radius: 10, y: 2)
    }

    private func actionRow(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        help: String,
        titleColor: Color = Theme.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12.5))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)
                Spacer()
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.inkGhost)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairlineSoft).frame(height: 0.7)
    }

    // MARK: 数据动作

    private var tagCount: Int {
        Set(memos.flatMap(\.tags)).count
    }

    private var imageCount: Int {
        memos.reduce(0) { $0 + $1.imageDatas.count }
    }

    private var storePath: String? {
        context.container.configurations.first?.url.path
    }

    private func exportWorkspaceBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 \(AppBrand.name) 备份"
        panel.nameFieldStringValue = WorkspaceBackup.filename()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        backupBusy = true
        dataNote = "正在导出备份…"
        Task { @MainActor in
            defer { backupBusy = false }
            do {
                let backup = try WorkspaceBackup.capture(from: context)
                try await Task.detached(priority: .utility) { try backup.write(to: url) }.value
                dataNote = "已备份 \(backup.counts.description)，保存为 \(url.lastPathComponent)。"
                app.showToast("已导出备份", icon: "arrow.down.document")
            } catch {
                dataNote = "导出失败。\(error.localizedDescription)"
            }
        }
    }

    private func restoreWorkspaceBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择 \(AppBrand.name) 备份文件"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        backupBusy = true
        dataNote = "正在读取备份…"
        Task { @MainActor in
            defer { backupBusy = false }
            do {
                let backup = try await Task.detached(priority: .utility) { try WorkspaceBackup.read(from: url) }.value
                let restored = try backup.restoreMissing(into: context)
                if restored.total > 0 {
                    let skipped = backup.counts.total - restored.total
                    dataNote = "已恢复 \(restored.description)。" + (skipped > 0 ? "跳过 \(skipped) 项本机已有内容。" : "")
                    app.showToast("备份恢复完成", icon: "arrow.counterclockwise")
                } else {
                    dataNote = backup.counts.total == 0 ? "这份备份没有可恢复的内容。" : "备份里的内容已在本机。"
                }
            } catch {
                dataNote = "恢复失败。\(error.localizedDescription)"
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "导出 \(AppBrand.name) 备份"
        panel.nameFieldStringValue = "\(AppBrand.name)-备份-\(DateText.dayKeyString(.now)).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MarkdownTransfer.export(memos: memos).write(to: url, atomically: true, encoding: .utf8)
            dataNote = "已导出 \(memos.count) 条笔记到 \(url.lastPathComponent)。"
            app.showToast("已导出 Markdown", icon: "square.and.arrow.up")
        } catch {
            dataNote = "导出失败：\(error.localizedDescription)"
            app.showToast("导出失败", icon: "exclamationmark.circle")
        }
    }

    private func importMarkdown(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            dataNote = "导入失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                dataNote = "读不出这个文件，确认它是 UTF-8 文本。"
                return
            }
            let parsed = MarkdownTransfer.parse(raw)
            guard !parsed.isEmpty else {
                dataNote = "没有识别到可导入的笔记。支持本 App 与 iPhone 版导出的 Markdown 格式。"
                return
            }

            var existing = Set(memos.map { "\($0.text)|\($0.createdAt.timeIntervalSince1970)" })
            var inserted = 0
            var firstID: UUID?
            for item in parsed {
                let key = "\(item.text)|\(item.date.timeIntervalSince1970)"
                guard existing.insert(key).inserted else { continue }
                let memo = Memo(text: item.text, createdAt: item.date)
                context.insert(memo)
                if firstID == nil { firstID = memo.id }
                inserted += 1
            }
            try? context.save()
            if inserted > 0 {
                app.selection = .all
                app.searchText = ""
                app.selectedMemoID = firstID
                dataNote = "导入了 \(inserted) 条笔记，跳过 \(parsed.count - inserted) 条重复内容。"
                app.showToast("导入完成", icon: "square.and.arrow.down")
            } else {
                dataNote = "这些笔记都已经在本机了，没有重复导入。"
            }
        }
    }

    private func revealStore() {
        guard let url = context.container.configurations.first?.url else {
            dataNote = "没有找到数据库文件位置。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func wipeMemosAndReviews() {
        for memo in memos { context.delete(memo) }
        for review in reviews { context.delete(review) }
        do {
            try context.save()
            app.selectedMemoID = nil
        } catch {
            context.rollback()
            dataNote = "笔记和回顾未能清空。"
            return
        }
        do {
            try aiReview.clearReport()
        } catch {
            dataNote = "笔记和每日回顾已清空，AI 回望结果未能清除。"
            return
        }
        dataNote = "本地笔记和回顾已清空。"
        app.showToast("已清空笔记和回顾", icon: "trash")
    }
}
