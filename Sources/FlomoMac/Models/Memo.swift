import Foundation
import SwiftData

/// 一条笔记。标签不独立建表，而是从正文中即时解析。
/// 这样编辑、撤销、粘贴时不会出现「正文改了、标签没改」的鬼数据。
@Model
final class Memo {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var imageDatas: [Data] = []

    init(text: String, createdAt: Date = .now, imageDatas: [Data] = []) {
        self.id = UUID()
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isPinned = false
        self.imageDatas = imageDatas
    }

    var tags: [String] { TagParser.uniqueTags(in: text) }

    var titleLine: String {
        let first = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        return first.isEmpty ? "（图片）" : first
    }

    var plainPreview: String {
        let clean = TagParser.removingTags(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? titleLine : clean
    }
}

/// 某天的回顾批次。固定当天的抽签结果，让「每日」这件事可复现。
@Model
final class DailyReview {
    @Attribute(.unique) var dayKey: String
    var day: Date
    var memoIDs: [UUID] = []
    var quota: Int = 5
    var completedAt: Date?

    init(day: Date, memoIDs: [UUID], quota: Int) {
        self.day = DateText.startOfDay(day)
        self.dayKey = DateText.dayKeyString(day)
        self.memoIDs = memoIDs
        self.quota = quota
        self.completedAt = nil
    }

    var isCompleted: Bool { completedAt != nil }
}
