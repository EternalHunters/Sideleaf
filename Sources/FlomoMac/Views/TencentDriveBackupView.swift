import AppKit
import SwiftData
import SwiftUI

struct TencentDriveBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var folder = "/"
    @State private var connected = false
    @State private var authorizing = false
    @State private var uploading = false
    @State private var status = "正在检查腾讯网盘授权…"
    @State private var localBackup: URL?

    let onUpload: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("备份到腾讯网盘")
                .font(.title3.weight(.semibold))
            Text("生成一份记录、图片、文章和待办的备份，并上传到你的网盘。")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("网盘目录", text: $folder, prompt: Text("/Sideleaf 备份"))
                    .disabled(uploading)
                Text("填写已有文件夹路径，/ 表示网盘根目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                if authorizing || uploading {
                    ProgressView().controlSize(.small)
                }
                Text(status)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)

            if let localBackup {
                Button("在访达中显示本地备份") {
                    NSWorkspace.shared.activateFileViewerSelecting([localBackup])
                }
            }

            HStack {
                Button(connected ? "重新授权" : "授权腾讯网盘") { authorizing = true }
                    .disabled(authorizing || uploading)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(uploading)
                Button(localBackup == nil ? "备份并上传" : "重新上传") { startUpload() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!connected || authorizing || uploading || TencentDrive.destination(for: folder) == nil)
            }
        }
        .padding(22)
        .frame(width: 480)
        .interactiveDismissDisabled(uploading)
        .task(id: authorizing) {
            if authorizing {
                await authorize()
            } else {
                await checkConnection()
            }
        }
    }

    private func checkConnection() async {
        do {
            connected = try await TencentDrive.connection().isConnected
            if status == "正在检查腾讯网盘授权…" {
                status = connected ? "腾讯网盘已授权。" : "首次上传需要授权 Sideleaf 访问腾讯网盘。"
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func authorize() async {
        defer { authorizing = false }
        status = "正在打开腾讯网盘授权页…"
        do {
            let url = try await TencentDrive.authorizationURL()
            try Task.checkCancellation()
            guard NSWorkspace.shared.open(url) else {
                status = "无法打开腾讯网盘授权页，请检查默认浏览器。"
                return
            }
            status = "请在浏览器中确认授权。完成后可以上传备份。"
            for _ in 0..<130 {
                try await Task.sleep(for: .seconds(5))
                let connection = try await TencentDrive.connection()
                switch connection.login?.state {
                case "denied", "expired", "failed", "mismatch":
                    status = "授权未完成，可以重新发起授权。"
                    return
                case "pending":
                    continue
                default:
                    if connection.isConnected {
                        connected = true
                        status = "腾讯网盘已授权。"
                        return
                    }
                }
            }
            status = "授权等待超时，可以重新发起授权。"
        } catch is CancellationError {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func startUpload() {
        guard !uploading, let destination = TencentDrive.destination(for: folder) else { return }
        uploading = true
        Task { @MainActor in
            defer { uploading = false }
            do {
                let file: URL
                if let localBackup {
                    file = localBackup
                } else {
                    status = "正在生成本地备份…"
                    let backup = try WorkspaceBackup.capture(from: context)
                    let directory = try FileManager.default.url(
                        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                    ).appendingPathComponent("flomo-mac/Backups", isDirectory: true)
                    file = directory.appendingPathComponent(WorkspaceBackup.filename())
                    try await Task.detached(priority: .utility) {
                        try FileManager.default.createDirectory(
                            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
                        )
                        try backup.write(to: file)
                    }.value
                    localBackup = file
                }
                status = "正在上传备份…"
                let path = try await TencentDrive.upload(file, to: destination)
                let message = path.map { "已上传到腾讯网盘「\($0)」。本机已保留备份文件。" }
                    ?? "已上传到腾讯网盘。本机已保留备份文件。"
                onUpload(message)
                dismiss()
            } catch {
                let prefix = localBackup == nil ? "未能生成本地备份。" : "本地备份已保存。"
                status = prefix + error.localizedDescription
                if let driveError = error as? TencentDrive.DriveError, case .commandFailed(3) = driveError {
                    connected = false
                }
            }
        }
    }
}
