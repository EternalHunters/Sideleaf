import Foundation
import SwiftData

@Model
final class Article {
    @Attribute(.unique) var id = UUID()
    var title = ""
    var markdown = ""
    var updatedAt = Date.now

    init() {}

    static func create(in context: ModelContext, title: String = "", markdown: String = "") throws -> Article {
        let article = Article()
        article.title = title
        article.markdown = markdown
        context.insert(article)
        do {
            try context.save()
            return article
        } catch {
            context.delete(article)
            throw error
        }
    }

    var displayTitle: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名文章" : name
    }
}

enum TodoStatus: String, CaseIterable, Identifiable {
    case pending
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待开始"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

@Model
final class TodoItem {
    @Attribute(.unique) var id = UUID()
    var title: String
    var details = ""
    var progress = ""
    var statusValue = TodoStatus.pending.rawValue
    // A calendar day stays the same when the user changes time zones.
    var dueDay: String?
    var updatedAt = Date.now
    @Relationship(deleteRule: .cascade, inverse: \TodoSubtask.todo)
    var subtasks: [TodoSubtask] = []

    init(title: String) {
        self.title = title
    }

    var status: TodoStatus {
        get { TodoStatus(rawValue: statusValue) ?? .pending }
        set { statusValue = newValue.rawValue }
    }

    func isOverdue(at date: Date) -> Bool {
        guard status != .completed, let dueDay else { return false }
        return dueDay < DateText.dayKeyString(date)
    }
}

@Model
final class TodoSubtask {
    @Attribute(.unique) var id = UUID()
    var title: String
    var isCompleted = false
    var position: Int
    var todo: TodoItem?

    init(title: String, position: Int) {
        self.title = title
        self.position = position
    }
}
