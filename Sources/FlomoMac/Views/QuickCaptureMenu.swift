import AppKit
import Observation
import SwiftData
import SwiftUI

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class QuickCaptureMenu: NSObject, NSApplicationDelegate, NSWindowDelegate {
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var appState: AppState?
    @ObservationIgnored private var container: ModelContainer?

    private(set) var isPinned = false
    private(set) var focusRequest = 0

    func configure(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.container = container
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = menuBarIcon()
        item.button?.toolTip = AppBrand.captureTitle
        item.button?.setAccessibilityLabel(AppBrand.captureTitle)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
        ProcessInfo.processInfo.disableAutomaticTermination(AppBrand.captureTitle)
    }

    private func menuBarIcon() -> NSImage? {
        guard let icon = NSApp.applicationIconImage else { return nil }
        let image = NSImage(size: NSSize(width: 19, height: 19), flipped: false) { bounds in
            icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = AppBrand.captureTitle
        return image
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let window = panel ?? makePanel() else { return }
        if !window.isVisible, !isPinned {
            position(window)
        }
        window.orderFrontRegardless()
        window.makeKey()
        focusRequest += 1
    }

    func hide() {
        guard let panel, panel.attachedSheet == nil else { return }
        panel.orderOut(nil)
    }

    func togglePin() {
        isPinned.toggle()
        panel?.level = isPinned ? .floating : .normal
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel() -> NSPanel? {
        guard let appState, let container else { return nil }
        let content = ComposerView(request: ComposerRequest(), quickCapture: self)
            .environment(appState)
            .modelContainer(container)
            .preferredColorScheme(.light)
            .tint(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16))

        let window = QuickCapturePanel(
            contentRect: NSRect(origin: .zero, size: ComposerView.quickCaptureSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = AppBrand.captureTitle
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: content)
        panel = window
        return window
    }

    private func position(_ window: NSPanel) {
        guard let button = statusItem?.button, let statusWindow = button.window,
              let screen = statusWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = window.frame.size
        let x = max(bounds.minX, min(anchor.midX - size.width / 2, bounds.maxX - size.width))
        let y = max(bounds.minY, min(anchor.minY - size.height - 5, bounds.maxY - size.height))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
