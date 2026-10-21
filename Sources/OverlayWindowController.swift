import AppKit

@MainActor
final class OverlayWindowController: NSWindowController, NSWindowDelegate, OverlayWindowControlling
{
    private let id: Overlay.ID
    private weak var store: OverlayStore?
    private let tintView: MetalTintView
    private let visibilityMask = CAShapeLayer()
    private var isApplying = false

    init(overlay: Overlay, store: OverlayStore) {
        self.id = overlay.id
        self.store = store
        self.tintView = MetalTintView(frame: CGRect(origin: .zero, size: overlay.frame.size))

        let panel = OverlayPanel(
            contentRect: overlay.frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.delegate = self
        panel.contentView = tintView
        visibilityMask.fillColor = NSColor.black.cgColor
        apply(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ overlay: Overlay) {
        guard let window else { return }
        isApplying = true
        defer { isApplying = false }
        if window.frame != overlay.frame {
            window.setFrame(overlay.frame, display: true, animate: false)
        }
        let canEdit = overlay.isEditing && !overlay.locked && overlay.isEnabled
        window.ignoresMouseEvents = !canEdit
        window.isMovable = canEdit
        if canEdit {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
        tintView.setAppearance(opacity: overlay.opacity, warmth: overlay.warmth)
        tintView.frame = window.contentView?.bounds ?? tintView.frame
        tintView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        tintView.layer?.borderWidth = canEdit ? 2 : 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let visibleRects = overlay.visibleRects {
            let path = CGMutablePath()
            for rect in visibleRects {
                path.addRect(rect.offsetBy(dx: -overlay.frame.minX, dy: -overlay.frame.minY))
            }
            visibilityMask.frame = tintView.bounds
            visibilityMask.path = path
            tintView.layer?.mask = visibilityMask
        } else {
            tintView.layer?.mask = nil
        }
        CATransaction.commit()

        if overlay.shouldShow {
            if !window.isVisible { window.orderFrontRegardless() }
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { reportFrame() }
    func windowDidResize(_ notification: Notification) {
        reportFrame()
        tintView.frame = window?.contentView?.bounds ?? tintView.frame
    }

    private func reportFrame() {
        guard !isApplying, let window, !window.ignoresMouseEvents else { return }
        let frame = window.frame
        store?.handleFrameChange(id: id, frame: frame)
    }
}

/// Borderless floating panel that sits above normal windows on every Space.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect, styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        // Sit above normal app windows but below system UI like the menu bar.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))

        // Show on every Space, survive full-screen transitions, don't appear in window cycling.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}
