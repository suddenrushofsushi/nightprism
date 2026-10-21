import AppKit
import Testing

@testable import Nightprism

@MainActor
struct OverlayWindowControllerTests {
    @Test
    func disabledAndNoneditingOverlayIsClickThroughAndNotResizable() throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }

        let window = try #require(harness.controller.window)
        #expect(window.ignoresMouseEvents)
        #expect(!window.isMovable)
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.isVisible)
    }

    @Test
    func editingEnablesMovementAndResizing() throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }
        var overlay = makeOverlay()
        overlay.isEnabled = true
        overlay.isEditing = true

        harness.controller.apply(overlay)

        let window = try #require(harness.controller.window)
        #expect(!window.ignoresMouseEvents)
        #expect(window.isMovable)
        #expect(window.styleMask.contains(.resizable))
    }

    @Test
    func lockingDisablesMovementAndResizingEvenIfEditingWasRequested() throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }
        var overlay = makeOverlay()
        overlay.isEnabled = true
        overlay.isEditing = true
        overlay.locked = true

        harness.controller.apply(overlay)

        let window = try #require(harness.controller.window)
        #expect(window.ignoresMouseEvents)
        #expect(!window.isMovable)
        #expect(!window.styleMask.contains(.resizable))
    }

    @Test
    func disabledAndHiddenTargetOverlaysStayHidden() throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }
        var disabled = makeOverlay()
        disabled.visibleRects = nil
        harness.controller.apply(disabled)
        #expect(harness.controller.window?.isVisible == false)

        var hiddenTarget = makeOverlay(target: makeTarget())
        hiddenTarget.isEnabled = true
        hiddenTarget.targetStatus = .hidden
        hiddenTarget.visibleRects = []
        harness.controller.apply(hiddenTarget)

        #expect(!hiddenTarget.shouldShow)
        #expect(harness.controller.window?.isVisible == false)
    }

    @Test
    func visibilityMaskContainsOnlyVisibleRectangles() throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }
        var overlay = makeOverlay()
        overlay.visibleRects = [
            CGRect(x: 0, y: 0, width: 40, height: 100),
            CGRect(x: 60, y: 0, width: 40, height: 100),
        ]

        harness.controller.apply(overlay)

        let mask = try #require(
            harness.controller.window?.contentView?.layer?.mask as? CAShapeLayer)
        let path = try #require(mask.path)
        #expect(path.contains(CGPoint(x: 20, y: 50)))
        #expect(!path.contains(CGPoint(x: 50, y: 50)))
        #expect(path.contains(CGPoint(x: 80, y: 50)))
    }

    private func makeOverlay(target: WindowTarget? = nil) -> Overlay {
        Overlay(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            opacity: 0.5,
            locked: false,
            isEnabled: false,
            target: target
        )
    }

    @Test
    func readsRealWindowMetadataAndProfilesSnapshots() async throws {
        let harness = try makeHarness(overlay: makeOverlay())
        defer { harness.close() }
        var overlay = makeOverlay()
        overlay.isEnabled = true
        harness.controller.apply(overlay)
        let window = try #require(harness.controller.window)
        let title = "Nightprism metadata test \(UUID().uuidString)"
        window.title = title
        window.level = .normal
        window.setFrame(CGRect(x: 35, y: 35, width: 103, height: 97), display: true)
        window.orderBack(nil)
        let height = try #require(NSScreen.screens.first).frame.maxY
        var match: [String: Any]?
        // Borderless window titles may be withheld. Match this test's unique geometry after
        // Window Server has had a run-loop turn to commit the newly created window.
        for _ in 0..<50 {
            let rows =
                CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
                ?? []
            match = rows.first {
                guard
                    ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                        == ProcessInfo.processInfo.processIdentifier,
                    let dictionary = $0[kCGWindowBounds as String] as? [String: Any]
                else { return false }
                var rect = CGRect.zero
                return CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &rect)
                    && WindowGeometry.appKitRect(from: rect, primaryScreenHeight: height)
                        == window.frame
            }
            if match != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let row = try #require(match)
        let id = try #require((row[kCGWindowNumber as String] as? NSNumber)?.uint32Value)
        let target = WindowTarget(
            id: id, ownerPID: ProcessInfo.processInfo.processIdentifier,
            appName: "Nightprism", title: title, frame: window.frame)
        let provider = SystemWindowSnapshotProvider()
        guard
            case .visible(let snapshot) = await provider.snapshot(
                for: target, primaryScreenHeight: height)
        else {
            Issue.record("Expected metadata for the real test window")
            return
        }
        #expect(snapshot.target.frame == window.frame)

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<100 {
            _ = await provider.snapshot(for: target, primaryScreenHeight: height)
        }
        let duration = start.duration(to: clock.now).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        print(
            String(
                format:
                    "Window metadata: 100 snapshots, %.3f ms mean (two CG queries per snapshot)",
                seconds * 10))
    }

    @Test
    func sameProcessNormalWindowOccludesButFloatingPanelDoesNot() async throws {
        let height = try #require(NSScreen.screens.first).frame.maxY
        let origin = try #require(NSScreen.screens.first).visibleFrame.origin
        let targetFrame = CGRect(x: origin.x + 40, y: origin.y + 80, width: 43, height: 37)
        let controlFrame = CGRect(x: origin.x + 140, y: origin.y + 180, width: 47, height: 41)
        let overlayFrame = CGRect(x: origin.x + 240, y: origin.y + 280, width: 53, height: 45)

        let targetWindow = NSWindow(
            contentRect: targetFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        let controlWindow = NSWindow(
            contentRect: controlFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        let overlayPanel = NSPanel(
            contentRect: overlayFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        defer {
            overlayPanel.close()
            controlWindow.close()
            targetWindow.close()
        }

        targetWindow.level = .normal
        controlWindow.level = .normal
        overlayPanel.level = .floating
        targetWindow.orderBack(nil)
        controlWindow.orderFrontRegardless()
        overlayPanel.orderFrontRegardless()

        var targetID: CGWindowID?
        for _ in 0..<50 {
            let rows =
                CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
                ?? []
            targetID = rows.first { row in
                guard
                    (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                        == ProcessInfo.processInfo.processIdentifier,
                    let dictionary = row[kCGWindowBounds as String] as? [String: Any]
                else { return false }
                var quartzFrame = CGRect.zero
                return CGRectMakeWithDictionaryRepresentation(
                    dictionary as CFDictionary, &quartzFrame)
                    && WindowGeometry.appKitRect(
                        from: quartzFrame, primaryScreenHeight: height) == targetFrame
            }.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
            if targetID != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        let target = WindowTarget(
            id: try #require(targetID),
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            appName: "Nightprism",
            title: "target window",
            frame: targetFrame
        )
        guard
            case .visible(let snapshot) = await SystemWindowSnapshotProvider().snapshot(
                for: target, primaryScreenHeight: height)
        else {
            Issue.record("Expected metadata for the real target window")
            return
        }

        #expect(snapshot.occluders.contains(controlFrame))
        #expect(!snapshot.occluders.contains(overlayFrame))
    }

    private func makeTarget() -> WindowTarget {
        WindowTarget(
            id: 42,
            ownerPID: 123,
            appName: "Example",
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
    }

    private func makeHarness(overlay: Overlay) throws -> Harness {
        let suiteName = "NightprismControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = OverlayStore(
            defaults: defaults,
            trackerFactory: { TestWindowTracker() },
            controllerFactory: { _, _ in TestController() }
        )
        return Harness(
            store: store,
            controller: OverlayWindowController(overlay: overlay, store: store),
            defaults: defaults,
            suiteName: suiteName
        )
    }
}

@MainActor
private final class Harness {
    let store: OverlayStore
    let controller: OverlayWindowController
    private let defaults: UserDefaults
    private let suiteName: String

    init(
        store: OverlayStore, controller: OverlayWindowController, defaults: UserDefaults,
        suiteName: String
    ) {
        self.store = store
        self.controller = controller
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func close() {
        controller.close()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestController: OverlayWindowControlling {
    func showWindow(_ sender: Any?) {}
    func close() {}
    func apply(_ overlay: Overlay) {}
}

@MainActor
private final class TestWindowTracker: WindowTracking {
    func start(
        target: WindowTarget,
        onUpdate: @escaping @MainActor @Sendable (WindowTrackingUpdate) -> Void
    ) {}

    func stop() {}
}
