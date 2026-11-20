import Foundation

enum TencentDrive {
    struct Connection: Decodable {
        struct Agent: Decodable { let connected: Bool }
        struct Login: Decodable { let state: String }

        let currentAgent: Agent?
        let login: Login?

        var isConnected: Bool { currentAgent?.connected == true }

        enum CodingKeys: String, CodingKey {
            case currentAgent = "current_agent"
            case login
        }
    }

    private struct Preflight: Decodable { let ok: Bool }

    private struct Response<Payload: Decodable>: Decodable {
        let code: Int
        let data: Payload?
    }

    static func connection() async throws -> Connection {
        let result = try await run(["account", "--agent-name", AppBrand.name])
        if result.status == 3 { return Connection(currentAgent: nil, login: nil) }
        return try result.payload(Connection.self)
    }

    static func authorizationURL() async throws -> URL {
        let preflight = try await run(["preflight"])
        guard try preflight.payload(Preflight.self).ok else { throw DriveError.localAccess }
        let result = try await run(["login", "-a", "--detach", "--agent-name", AppBrand.name])
        guard result.status == 0 else { throw DriveError.commandFailed(result.status) }
        let output = String(decoding: result.output, as: UTF8.self)
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in: output, range: NSRange(output.startIndex..., in: output))
        guard let url = matches.compactMap(\.url).first(where: {
            $0.scheme == "https" && $0.host == "drive.tencent.com" && $0.user == nil && $0.password == nil
        }) else { throw DriveError.invalidReply }
        return url
    }

    static func destination(for input: String) -> String? {
        let folder = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard folder.hasPrefix("/") else { return nil }
        let segments = folder.split(separator: "/")
        let forbidden = CharacterSet(charactersIn: "\\:*?\"<>|").union(.controlCharacters)
        guard segments.allSatisfy({ part in
            part != "." && part != ".." && part.utf16.count <= 256 && part.rangeOfCharacter(from: forbidden) == nil
        }) else { return nil }
        return segments.isEmpty ? "tdrive:/" : "tdrive:/" + segments.joined(separator: "/") + "/"
    }

    static func upload(_ file: URL, to destination: String) async throws -> String? {
        let result = try await run([
            "cp", file.path, destination, "--conflict", "rename", "--agent-name", AppBrand.name
        ])
        guard result.status == 0 else { throw DriveError.commandFailed(result.status) }
        guard let reply = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
              reply["code"] as? Int == 0,
              let payload = reply["data"] as? [String: Any],
              payload["mode"] as? String == "upload",
              let fileID = payload["file_id"], !(fileID is NSNull),
              let source = payload["source_agent"], !(source is NSNull) else {
            throw DriveError.invalidReply
        }
        return payload["dst"] as? String
    }

    private struct CommandResult: Sendable {
        let status: Int32
        let output: Data

        func payload<T: Decodable>(_ type: T.Type) throws -> T {
            guard status == 0 else { throw DriveError.commandFailed(status) }
            guard let reply = try? JSONDecoder().decode(Response<T>.self, from: output),
                  reply.code == 0, let data = reply.data else { throw DriveError.invalidReply }
            return data
        }
    }

    private static func run(_ arguments: [String]) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [
                home.appendingPathComponent(".local/bin/tdrive"),
                home.appendingPathComponent(".local/share/tdrive/bin/tdrive"),
                URL(fileURLWithPath: "/opt/homebrew/bin/tdrive"),
                URL(fileURLWithPath: "/usr/local/bin/tdrive")
            ]
            guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                throw DriveError.missingCLI
            }
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments + ["--json"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus, output: data)
        }.value
    }

    enum DriveError: LocalizedError {
        case missingCLI, localAccess, invalidReply, commandFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .missingCLI: return "未找到腾讯网盘命令行工具。请先安装腾讯网盘官方 CLI。"
            case .localAccess: return "腾讯网盘无法写入本机的授权目录，请检查文件访问权限。"
            case .invalidReply: return "无法确认腾讯网盘操作结果，请到网盘查看。"
            case .commandFailed(3): return "Sideleaf 的腾讯网盘授权已失效，请重新授权。"
            case .commandFailed(4): return "连不上腾讯网盘，请检查网络后重试。"
            case .commandFailed(5): return "找不到这个网盘目录，请检查路径。"
            case .commandFailed(8): return "当前账号没有这个目录的写入权限。"
            case .commandFailed(13): return "腾讯网盘空间不足。"
            case .commandFailed(15): return "腾讯网盘无法访问本机所需文件，请检查文件访问权限。"
            case .commandFailed: return "腾讯网盘操作失败，请检查授权、网络和目标文件夹。"
            }
        }
    }
}
