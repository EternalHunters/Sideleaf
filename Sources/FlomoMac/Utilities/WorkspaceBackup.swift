import Foundation
import SwiftData

struct WorkspaceBackup: Codable, Sendable {
    private static let formatName = "sideleaf-backup"
    private static let currentVersion = 1

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct Record: Codable, Sendable {
        let id: UUID
        let text: String
        let createdAt: Date
        let updatedAt: Date
        let isPinned: Bool
        let images: [Data]
    }

    private struct Draft: Codable, Sendable {
        let id: UUID
        let title: String
        let markdown: String
        let updatedAt: Date
    }

    private struct TaskItem: Codable, Sendable {
        struct Subtask: Codable, Sendable {
            let id: UUID
            let title: String
            let isCompleted: Bool
            let position: Int
        }

        let id: UUID
        let title: String
        let details: String
        let progress: String
        let status: String
        let dueDay: String?
        let updatedAt: Date
        let subtasks: [Subtask]
    }

    struct Counts {
        var records = 0
        var drafts = 0
        var tasks = 0

        var total: Int { records + drafts + tasks }
        var description: String { "\(records) 条记录、\(drafts) 篇文章、\(tasks) 项待办" }
    }

    private let format: String
    private let version: Int
    private let exportedAt: Date
    private let records: [Record]
    private let drafts: [Draft]
    private let tasks: [TaskItem]

    var counts: Counts { Counts(records: records.count, drafts: drafts.count, tasks: tasks.count) }

    static func filename() -> String {
        let timestamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        return "Sideleaf-备份-\(timestamp)-\(UUID().uuidString.prefix(8)).json"
    }

    @MainActor
    static func capture(from context: ModelContext) throws -> Self {
        let records = try context.fetch(FetchDescriptor<Memo>(sortBy: [SortDescriptor(\.createdAt)]))
        let drafts = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.updatedAt)]))
        let tasks = try context.fetch(FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.updatedAt)]))
        return Self(
            format: formatName,
            version: currentVersion,
            exportedAt: .now,
            records: records.map { memo in
                Record(id: memo.id, text: memo.text, createdAt: memo.createdAt, updatedAt: memo.updatedAt,
                       isPinned: memo.isPinned, images: memo.imageDatas)
            },
            drafts: drafts.map { article in
                Draft(id: article.id, title: article.title, markdown: article.markdown, updatedAt: article.updatedAt)
            },
            tasks: tasks.map { todo in
                TaskItem(id: todo.id, title: todo.title, details: todo.details, progress: todo.progress,
                         status: todo.statusValue, dueDay: todo.dueDay, updatedAt: todo.updatedAt,
                         subtasks: todo.subtasks.sorted { $0.position < $1.position }.map {
                    TaskItem.Subtask(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, position: $0.position)
                })
            }
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> Self {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName else {
            throw BackupError.invalidFile
        }
        guard header.version == currentVersion else { throw BackupError.unsupportedVersion }
        guard let backup = try? decoder.decode(Self.self, from: data) else { throw BackupError.invalidFile }
        let subtaskIDs = backup.tasks.flatMap { $0.subtasks.map(\.id) }
        guard Set(backup.records.map(\.id)).count == backup.records.count,
              Set(backup.drafts.map(\.id)).count == backup.drafts.count,
              Set(backup.tasks.map(\.id)).count == backup.tasks.count,
              Set(subtaskIDs).count == subtaskIDs.count else {
            throw BackupError.duplicateIDs
        }
        return backup
    }

    @MainActor
    func restoreMissing(into context: ModelContext) throws -> Counts {
        let existingRecords = Set(try context.fetch(FetchDescriptor<Memo>()).map(\.id))
        let existingDrafts = Set(try context.fetch(FetchDescriptor<Article>()).map(\.id))
        let existingTasks = Set(try context.fetch(FetchDescriptor<TodoItem>()).map(\.id))
        let existingSubtasks = Set(try context.fetch(FetchDescriptor<TodoSubtask>()).map(\.id))
        let newRecords = records.filter { !existingRecords.contains($0.id) }
        let newDrafts = drafts.filter { !existingDrafts.contains($0.id) }
        let newTasks = tasks.filter { !existingTasks.contains($0.id) }
        guard existingSubtasks.isDisjoint(with: newTasks.flatMap { $0.subtasks.map(\.id) }) else {
            throw BackupError.duplicateIDs
        }
        let restored = Counts(records: newRecords.count, drafts: newDrafts.count, tasks: newTasks.count)
        guard restored.total > 0 else { return restored }

        // Commit pending edits first so a failed restore can roll back just these inserts.
        if context.hasChanges { try context.save() }
        for record in newRecords {
            let memo = Memo(text: record.text, createdAt: record.createdAt, imageDatas: record.images)
            memo.id = record.id
            memo.updatedAt = record.updatedAt
            memo.isPinned = record.isPinned
            context.insert(memo)
        }
        for draft in newDrafts {
            let article = Article()
            article.id = draft.id
            article.title = draft.title
            article.markdown = draft.markdown
            article.updatedAt = draft.updatedAt
            context.insert(article)
        }
        for task in newTasks {
            let todo = TodoItem(title: task.title)
            todo.id = task.id
            todo.details = task.details
            todo.progress = task.progress
            todo.statusValue = task.status
            todo.dueDay = task.dueDay
            todo.updatedAt = task.updatedAt
            context.insert(todo)
            for item in task.subtasks {
                let subtask = TodoSubtask(title: item.title, position: item.position)
                subtask.id = item.id
                subtask.isCompleted = item.isCompleted
                context.insert(subtask)
                todo.subtasks.append(subtask)
            }
        }
        do {
            try context.save()
            return restored
        } catch {
            context.rollback()
            throw error
        }
    }

    private enum BackupError: LocalizedError {
        case invalidFile, unsupportedVersion, duplicateIDs

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "这个文件不是完整的 Sideleaf 备份。"
            case .unsupportedVersion: return "这个备份的格式版本暂不支持。"
            case .duplicateIDs: return "备份里的数据 ID 重复或与本机冲突，无法恢复。"
            }
        }
    }
}
