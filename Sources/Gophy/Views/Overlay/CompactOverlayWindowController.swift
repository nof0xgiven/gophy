import SwiftUI
import AppKit

@MainActor
final class CompactOverlayWindowController {
    static let shared = CompactOverlayWindowController()

    private var panel: NSPanel?
    private let frameKey = "compactOverlayFrame"

    private init() {}

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func showOverlay() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }

        let savedFrame = UserDefaults.standard.string(forKey: frameKey)
        let frame: CGRect
        if let savedFrame, let decoded = decodeFrame(savedFrame) {
            frame = decoded
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            let overlayWidth: CGFloat = 320
            let overlayHeight: CGFloat = 200
            frame = CGRect(
                x: screenFrame.maxX - overlayWidth - 20,
                y: screenFrame.maxY - overlayHeight - 20,
                width: overlayWidth,
                height: overlayHeight
            )
        }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovable = true
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(
            rootView: CompactOverlayView(
                onClose: { [weak self] in
                    self?.hideOverlay()
                }
            )
        )
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            self?.saveFrame()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            self?.saveFrame()
        }
    }

    func hideOverlay() {
        panel?.orderOut(nil)
    }

    func toggleOverlay() {
        if isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func saveFrame() {
        guard let frame = panel?.frame else { return }
        let encoded = "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
        UserDefaults.standard.set(encoded, forKey: frameKey)
    }

    private func decodeFrame(_ encoded: String) -> CGRect? {
        let parts = encoded.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}
