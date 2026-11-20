import AppKit
import SwiftData
import SwiftUI

struct TodoBrowserView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.updatedAt, order: .reverse) private var todos: [TodoItem]

    @State private var filter: Filter = .open
    @State private var newTitle = ""
    @FocusState private var titleFocused: Bool

    private enum Filter: String, CaseIterable {
        case open = "未完成"
        case completed = "已完成"
        case all = "全部"
    }

    private var visibleTodos: [TodoItem] {
        let matching = todos.filter { todo in
            switch filter {
            case .open: return todo.status != .completed
            case .completed: return todo.status == .completed
            case .all: return true
            }
        }
        return matching.sorted { first, second in
            let firstDone = first.status == .completed
            let secondDone = second.status == .completed
            if firstDone != secondDone { return !firstDone }
            if !firstDone, first.dueDay != second.dueDay {
                if let firstDay = first.dueDay {
                    return second.dueDay.map { firstDay < $0 } ?? true
                }
                return false
            }
            return first.updatedAt > second.updatedAt
        }
    }

    var body: some View {
        let visible = visibleTodos
        TimelineView(.everyMinute) { time in
            WorkspaceList(
                title: "待办", count: visible.count,
                emptyMessage: filter == .completed ? "还没有完成的待办" : "没有待办",
                createAction: nil
            ) {
                VStack(spacing: 12) {
                    quickAdd
                    Picker("筛选待办", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: filter) {
                        if !visibleTodos.contains(where: { $0.id == app.selectedTodoID }) {
                            app.selectedTodoID = nil
                        }
                    }
                }
                .padding(.bottom, 13)
            } rows: {
                ForEach(visible, id: \.id) { todo in
                    todoRow(todo, now: time.date)
                }
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            TextField("快速新建待办", text: $newTitle, prompt: Text("输入任务标题，按回车添加"))
                .textFieldStyle(.plain)
                .font(Theme.body(14))
                .focused($titleFocused)
                .onSubmit(createTodo)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(titleFocused ? Theme.accent : Theme.hairline, lineWidth: 1)
        }
        .onTapGesture { titleFocused = true }
    }

    private func todoRow(_ todo: TodoItem, now: Date) -> some View {
        let selected = app.selectedTodoID == todo.id
        let completionAction = todo.status == .completed ? "取消完成" : "标记完成"
        return WorkspaceRow(selected: selected) {
            HStack(alignment: .top, spacing: 0) {
                Button { toggleCompletion(todo) } label: {
                    Image(systemName: todo.status.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(todo.status == .pending ? Theme.inkSoft : Theme.accentDeep)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(completionAction)「\(todo.title)」")
                .help(completionAction)

                Button { app.selectedTodoID = todo.id } label: {
                    todoSummary(todo, now: now)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.trailing, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func todoSummary(_ todo: TodoItem, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(todo.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if !todo.subtasks.isEmpty {
                    let completed = todo.subtasks.filter(\.isCompleted).count
                    Text("\(completed)/\(todo.subtasks.count)")
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityLabel("子任务已完成 \(completed) 项，共 \(todo.subtasks.count) 项")
                }
            }
            HStack(spacing: 8) {
                Text(todo.status.title)
                if let day = todo.dueDay {
                    TodoDueLabel(day: day, overdue: todo.isOverdue(at: now))
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSoft)
        }
    }

    private func toggleCompletion(_ todo: TodoItem) {
        let reopening = todo.status == .completed
        todo.status = reopening ? .pending : .completed
        todo.updatedAt = .now
        do {
            try context.save()
            app.showToast(reopening ? "已取消完成" : "待办已完成")
        } catch {
            context.rollback()
            app.showToast("待办状态未能更新", icon: "exclamationmark.circle")
        }
    }

    private func createTodo() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let todo = TodoItem(title: title)
        context.insert(todo)
        do {
            try context.save()
            if filter == .completed { filter = .open }
            app.selectedTodoID = todo.id
            newTitle = ""
        } catch {
            context.delete(todo)
            app.showToast("待办未能新建", icon: "exclamationmark.circle")
        }
    }
}

struct TodoDetailView: View {
    @Environment(AppState.self) private var app
    @Query private var todos: [TodoItem]

    var body: some View {
        if let todo = todos.first(where: { $0.id == app.selectedTodoID }) {
            TodoEditor(todo: todo)
                .id(todo.id)
        } else {
            WorkspaceEmptyState(title: "选择或新建一条待办", icon: "checklist")
        }
    }
}

private struct TodoEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    private let todo: TodoItem
    @State private var draft: Draft
    @State private var newSubtask = ""
    @State private var editingDeadline = false
    @State private var deadline = Date.now
    @State private var confirmingDeletion = false
    @State private var deleted = false
    @State private var saveFailed = false

    private struct Draft: Equatable {
        var title: String
        var details: String
        var progress: String

        init(_ todo: TodoItem) {
            title = todo.title
            details = todo.details
            progress = todo.progress
        }
    }

    init(todo: TodoItem) {
        self.todo = todo
        _draft = State(initialValue: Draft(todo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                toolbar

                TextField("任务标题", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(Theme.detailTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("任务标题")

                Divider()

                textSection("描述", prompt: "添加任务描述", text: $draft.details)

                subtaskSection

                textSection("进展", prompt: "记录当前进展", text: $draft.progress)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .task(id: draft) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            saveDraft()
        }
        .onDisappear { saveDraft(reportFailure: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveDraft()
        }
        .alert("删除这条待办？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteTodo)
        } message: {
            Text("这条待办和其中的子任务都会删除。")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("任务状态", selection: Binding(
                get: { todo.status },
                set: { status in
                    if todo.status != status { save { todo.status = status } }
                }
            )) {
                ForEach(TodoStatus.allCases) { status in
                    Label(status.title, systemImage: status.icon).tag(status)
                }
            }
            .labelsHidden()
            .fixedSize()

            Button {
                deadline = todo.dueDay.flatMap(DateText.date(dayKey:)) ?? .now
                editingDeadline = true
            } label: {
                TimelineView(.everyMinute) { time in
                    if let day = todo.dueDay {
                        TodoDueLabel(day: day, overdue: todo.isOverdue(at: time.date))
                    } else {
                        Label("设置到期日", systemImage: "calendar")
                    }
                }
            }
            .buttonStyle(.borderless)
            .help("编辑到期日")
            .popover(isPresented: $editingDeadline, arrowEdge: .bottom) {
                deadlinePicker
            }

            Spacer(minLength: 0)

            if saveFailed {
                Button("保存失败，重试") { saveDraft(reportFailure: true) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.danger)
            }

            if todo.status != .completed {
                Button { save { todo.status = .completed } } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
            }

            Menu {
                Button("删除待办", role: .destructive) { confirmingDeletion = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("待办操作")
        }
        .font(Theme.caption)
    }

    private var deadlinePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("到期日", selection: $deadline, displayedComponents: .date)
                .environment(\.calendar, DateText.cal)
            HStack {
                if todo.dueDay != nil {
                    Button("清除") { setDeadline(nil) }
                }
                Spacer()
                Button("保存") { setDeadline(DateText.dayKeyString(deadline)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 230)
    }

    private func setDeadline(_ day: String?) {
        if save({ todo.dueDay = day }) { editingDeadline = false }
    }

    private var subtaskSection: some View {
        let subtasks = todo.subtasks.sorted { $0.position < $1.position }
        let done = subtasks.filter(\.isCompleted).count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionTitle("子任务")
                if !subtasks.isEmpty {
                    Text("\(done)/\(subtasks.count) 已完成")
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            VStack(spacing: 0) {
                ForEach(subtasks, id: \.id) { subtask in
                    subtaskRow(subtask)
                    Divider().padding(.leading, 12)
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.accentDeep)
                        .accessibilityHidden(true)
                    TextField("添加子任务", text: $newSubtask, prompt: Text("添加子任务，按回车保存"))
                        .textFieldStyle(.plain)
                        .onSubmit(addSubtask)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
            }
            .font(Theme.body(14))
            .flomoCard(radius: 10)
        }
    }

    private func subtaskRow(_ subtask: TodoSubtask) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { subtask.isCompleted },
                set: { completed in save { subtask.isCompleted = completed } }
            )) {
                Text(subtask.title)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted ? Theme.inkSoft : Theme.ink)
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 4)

            SubtaskActions(subtask: subtask) { title in
                save { subtask.title = title }
            } delete: {
                save { context.delete(subtask) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let position = (todo.subtasks.map(\.position).max() ?? -1) + 1
        let subtask = TodoSubtask(title: title, position: position)
        if save({
            context.insert(subtask)
            todo.subtasks.append(subtask)
        }) {
            newSubtask = ""
        }
    }

    private func textSection(_ title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            TextField(title, text: text, prompt: Text(prompt), axis: .vertical)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
                .textFieldStyle(.plain)
                .lineLimit(3...10)
                .padding(12)
                .flomoCard(radius: 10)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private var hasDraftChanges: Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleChanged = !title.isEmpty && title != todo.title
        return titleChanged || draft.details != todo.details || draft.progress != todo.progress
    }

    private func saveDraft(reportFailure: Bool = false) {
        guard !deleted, hasDraftChanges else { return }
        save(reportFailure: reportFailure)
    }

    @discardableResult
    private func save(reportFailure: Bool = true, _ edit: () -> Void = {}) -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { todo.title = title }
        todo.details = draft.details
        todo.progress = draft.progress
        todo.updatedAt = .now
        edit()

        do {
            try context.save()
            saveFailed = false
            return true
        } catch {
            context.rollback()
            saveFailed = hasDraftChanges
            if reportFailure {
                app.showToast("待办改动未能保存", icon: "exclamationmark.circle")
            }
            return false
        }
    }

    private func deleteTodo() {
        if save({ context.delete(todo) }) {
            deleted = true
            app.selectedTodoID = nil
            app.showToast("已删除待办", icon: "trash")
        }
    }
}

private struct SubtaskActions: View {
    let subtask: TodoSubtask
    let rename: (String) -> Void
    let delete: () -> Void

    @State private var editingName = false
    @State private var newName = ""
    @State private var confirmingDeletion = false

    var body: some View {
        Menu {
            Button("重命名") {
                newName = subtask.title
                editingName = true
            }
            Button("删除子任务", role: .destructive) { confirmingDeletion = true }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.inkSoft)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("子任务操作")
        .alert("重命名子任务", isPresented: $editingName) {
            TextField("子任务标题", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { rename(title) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("删除这条子任务？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: delete)
        } message: {
            Text(subtask.title)
        }
    }
}

private struct TodoDueLabel: View {
    let day: String
    let overdue: Bool

    var body: some View {
        Label(overdue ? "已过期 · \(day)" : "到期 \(day)", systemImage: overdue ? "clock.badge.exclamationmark" : "calendar")
            .foregroundStyle(overdue ? Theme.danger : Theme.inkSoft)
            .monospacedDigit()
    }
}
