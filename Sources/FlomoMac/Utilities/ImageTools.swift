import Foundation
import AppKit

enum ImageTools {
    /// 落库前把图片压到长边 1800、JPEG 0.8。
    /// 笔记里的图片主要是“看见当时的场景”，不是原图存档。
    static func compress(_ data: Data, maxEdge: CGFloat = 1800, quality: CGFloat = 0.8) -> Data {
        guard let image = NSImage(data: data) else { return data }
        let source = image.size
        guard source.width > 0, source.height > 0 else { return data }

        let scale = min(1, maxEdge / max(source.width, source.height))
        let target = NSSize(width: source.width * scale, height: source.height * scale)

        let canvas = NSImage(size: target)
        canvas.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: target)).fill()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: source),
            operation: .sourceOver,
            fraction: 1
        )
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        else { return data }
        return jpeg
    }

    static func readSecurityScoped(_ url: URL) -> Data? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}
