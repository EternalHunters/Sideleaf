import Foundation
import Observation
import SwiftData

enum SyncError: LocalizedError {
    case notConfigured(String)
    case badURL
    case unauthorized
    case http(Int, String)
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message): return message
        case .badURL: return "服务地址格式不对，检查一下 http:// 或 https://"
        case .unauthorized: return "登录已失效，请重新连接"
        case .http(let code, let body):
            let brief = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = brief.count > 180 ? String(brief.prefix(180)) + "…" : brief
            if code == 429 { return "操作太频繁了，等一分钟再试" }
            return "服务返回 \(code)\(shown.isEmpty ? "" : "：\(shown)")"
        case .badResponse: return "无法识别同步接口的响应，请检查服务地址"
        case .server(let message): return message
        }
    }
}

// MARK: - Wire types

private struct AuthRequest: Encodable {
    let name: String
    let password: String
    let signupKey: String?

    enum CodingKeys: String, CodingKey {
        case name, password
        case signupKey = "signup_key"
    }
}

private struct AuthResponse: Decodable {
    let userID: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case token
        case userID = "user_id"
    }
}

private struct PushMemo: Encodable {
    let id: String
    let content: String
    let tags: [String]
    let clientTS: Int64
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, content, tags, deleted
        case clientTS = "client_ts"
    }
}

private struct PushRequest: Encodable {
    let deviceID: String
    let memos: [PushMemo]

    enum CodingKeys: String, CodingKey {
        case memos
        case deviceID = "device_id"
    }
}

private struct PushResult: Decodable {
    let id: String
    let status: String
    let serverSeq: Int64

    enum CodingKeys: String, CodingKey {
        case id, status
        case serverSeq = "server_seq"
    }
}

private struct PushResponse: Decodable {
    let results: [PushResult]
    let conflicts: Int
}

private struct PullMemo: Decodable {
    let id: String
    let content: String
    let clientTS: Int64
    let serverTS: Int64
    let serverSeq: Int64
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, content, deleted
        case clientTS = "client_ts"
        case serverTS = "server_ts"
        case serverSeq = "server_seq"
    }
}

private struct PullResponse: Decodable {
    let memos: [PullMemo]
    let nextSince: Int64
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case memos
        case nextSince = "next_since"
        case hasMore = "has_more"
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}

// MARK: - Manager

@MainActor
@Observable
final class SyncManager {
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "sync.baseURL") }
    }
    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "sync.username") }
    }
    var password: String {
        didSet { Keychain.set(password, for: "password") }
    }
    var token: String {
        didSet { Keychain.set(token, for: "token") }
    }
    var lastSeq: Int64 {
        didSet { UserDefaults.standard.set(Int(lastSeq), forKey: "sync.lastSeq") }
    }
    var lastSyncAt: Date? {
        didSet {
            if let date = lastSyncAt {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "sync.lastSyncAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "sync.lastSyncAt")
            }
        }
    }

    var busy = false
    var note: String?
    var noteIsError = false
    var signupKey = ""

    let deviceID: String

    init() {
        let defaults = UserDefaults.standard
        baseURL = defaults.string(forKey: "sync.baseURL") ?? ""
        username = defaults.string(forKey: "sync.username") ?? ""
        password = Keychain.get("password")
        token = Keychain.get("token")
        lastSeq = Int64(defaults.integer(forKey: "sync.lastSeq"))
        if let timestamp = defaults.object(forKey: "sync.lastSyncAt") as? Double {
            lastSyncAt = Date(timeIntervalSince1970: timestamp)
        }
        if let existing = defaults.string(forKey: "sync.deviceID"), !existing.isEmpty {
            deviceID = existing
        } else {
            let fresh = "mac-" + UUID().uuidString
            defaults.set(fresh, forKey: "sync.deviceID")
            deviceID = fresh
        }
    }

    var normalizedBase: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var hasCredentials: Bool {
        !normalizedBase.isEmpty && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConnected: Bool { hasCredentials && !token.isEmpty }

    var statusLine: String {
        if !hasCredentials { return "未配置" }
        if token.isEmpty { return "未登录" }
        guard let lastSyncAt else { return "已连接" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return "上次 \(f.string(from: lastSyncAt))"
    }

    // MARK: Auth

    func login() async -> Bool {
        await perform {
            try await self.authenticate(path: "/api/v1/auth/login", signup: false)
            self.note = "连接成功"
            return "连接成功"
        }
    }

    func register() async -> Bool {
        await perform {
            try await self.authenticate(path: "/api/v1/auth/register", signup: true)
            self.note = "账号已创建并连接"
            return "账号已创建并连接"
        }
    }

    private func authenticate(path: String, signup: Bool) async throws {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            throw SyncError.notConfigured("先把用户名和密码填上")
        }
        let key = signupKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = AuthRequest(
            name: user,
            password: password,
            signupKey: signup && !key.isEmpty ? key : nil
        )
        let response: AuthResponse = try await send(
            path: path,
            method: "POST",
            body: body,
            token: nil
        )
        token = response.token
    }

    func disconnect() {
        token = ""
        lastSeq = 0
        lastSyncAt = nil
        note = nil
        noteIsError = false
    }

    // MARK: Push

    func upload(memos: [Memo]) async -> Bool {
        await perform {
            guard self.hasCredentials else {
                throw SyncError.notConfigured("先在同步设置里填好服务器地址和账号")
            }
            let textMemos = memos.filter { $0.imageDatas.isEmpty }
            let skipped = memos.count - textMemos.count
            guard !textMemos.isEmpty else {
                return skipped > 0 ? "\(skipped) 条笔记只有图片，暂不支持同步" : "还没有笔记可以上传"
            }

            var created = 0
            var updated = 0
            var unchanged = 0
            var conflicts = 0
            var maxSeq = self.lastSeq

            for chunk in textMemos.chunked(into: 200) {
                let request = PushRequest(
                    deviceID: self.deviceID,
                    memos: chunk.map { memo in
                        PushMemo(
                            id: memo.id.uuidString,
                            content: memo.text,
                            tags: memo.tags,
                            clientTS: Int64(memo.createdAt.timeIntervalSince1970 * 1000),
                            deleted: false
                        )
                    }
                )
                let response: PushResponse = try await self.authed(
                    path: "/api/v1/sync/push",
                    method: "POST",
                    body: request
                )
                conflicts += response.conflicts
                for item in response.results {
                    maxSeq = max(maxSeq, item.serverSeq)
                    switch item.status {
                    case "created": created += 1
                    case "updated", "conflict_overwritten": updated += 1
                    default: unchanged += 1
                    }
                }
            }

            self.lastSeq = maxSeq
            self.lastSyncAt = .now

            var parts: [String] = []
            if created > 0 { parts.append("新增 \(created) 条") }
            if updated > 0 { parts.append("更新 \(updated) 条") }
            if unchanged > 0 { parts.append("\(unchanged) 条已在云端") }
            if skipped > 0 { parts.append("\(skipped) 条含图片未上传") }
            if conflicts > 0 { parts.append("\(conflicts) 条发生覆盖") }
            let summary = parts.isEmpty ? "没有需要上传的内容" : parts.joined(separator: "，")
            self.note = summary
            return summary
        }
    }

    // MARK: Pull

    func download(context: ModelContext) async -> Bool {
        await perform {
            guard self.hasCredentials else {
                throw SyncError.notConfigured("先在同步设置里填好服务器地址和账号")
            }

            let local = try context.fetch(FetchDescriptor<Memo>())
            var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

            var since = self.lastSeq
            var inserted = 0
            var updated = 0
            var removed = 0
            var skipped = 0
            var pages = 0
            var hasMore = true

            while hasMore && pages < 100 {
                pages += 1
                let page: PullResponse = try await self.authed(
                    path: "/api/v1/sync/pull?since=\(since)&limit=200",
                    method: "GET",
                    body: Optional<PushRequest>.none
                )

                for remote in page.memos {
                    guard let uuid = UUID(uuidString: remote.id) else {
                        skipped += 1
                        continue
                    }

                    if remote.deleted {
                        if let memo = byID.removeValue(forKey: uuid) {
                            context.delete(memo)
                            removed += 1
                        }
                        continue
                    }

                    if let existing = byID[uuid] {
                        if existing.text != remote.content {
                            existing.text = remote.content
                            existing.updatedAt = Self.date(millis: remote.serverTS)
                            updated += 1
                        }
                    } else {
                        let memo = Memo(
                            text: remote.content,
                            createdAt: Self.date(millis: remote.clientTS > 0 ? remote.clientTS : remote.serverTS)
                        )
                        memo.id = uuid
                        memo.updatedAt = Self.date(millis: remote.serverTS)
                        context.insert(memo)
                        byID[uuid] = memo
                        inserted += 1
                    }
                }

                since = page.nextSince
                hasMore = page.hasMore
            }

            if inserted + updated + removed > 0 {
                try context.save()
            }
            self.lastSeq = since
            self.lastSyncAt = .now

            var parts: [String] = []
            if inserted > 0 { parts.append("新增 \(inserted) 条") }
            if updated > 0 { parts.append("更新 \(updated) 条") }
            if removed > 0 { parts.append("删除 \(removed) 条") }
            if skipped > 0 { parts.append("\(skipped) 条 id 格式不认识") }
            let summary = parts.isEmpty ? "已经是最新的了" : parts.joined(separator: "，")
            self.note = summary
            return summary
        }
    }

    // MARK: Networking

    private func perform(_ operation: @escaping () async throws -> String) async -> Bool {
        guard !busy else { return false }
        busy = true
        note = nil
        noteIsError = false
        do {
            note = try await operation()
            noteIsError = false
            busy = false
            return true
        } catch {
            note = error.localizedDescription
            noteIsError = true
            busy = false
            return false
        }
    }

    private func authed<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: Body?,
        token: String
    ) async throws -> T {
        do {
            return try await send(path: path, method: method, body: body, token: token)
        } catch SyncError.unauthorized {
            self.token = ""
            try await authenticate(path: "/api/v1/auth/login", signup: false)
            return try await send(path: path, method: method, body: body, token: self.token)
        }
    }

    private func authed<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> T {
        let usable = try await ensureToken()
        return try await authed(path: path, method: method, body: body, token: usable)
    }

    private func ensureToken() async throws -> String {
        if !token.isEmpty { return token }
        try await authenticate(path: "/api/v1/auth/login", signup: false)
        return token
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: Body?,
        token: String?
    ) async throws -> T {
        let base = normalizedBase
        guard !base.isEmpty, let url = URL(string: base + path) else { throw SyncError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badResponse }
        if http.statusCode == 401 { throw SyncError.unauthorized }

        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw SyncError.http(http.statusCode, envelope.error ?? "")
        }
        guard envelope.ok, let payload = envelope.data else {
            throw SyncError.server(envelope.error ?? "服务返回了空数据")
        }
        return payload
    }

    private static func date(millis: Int64) -> Date {
        millis > 0 ? Date(timeIntervalSince1970: Double(millis) / 1000) : .now
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, count > size else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
