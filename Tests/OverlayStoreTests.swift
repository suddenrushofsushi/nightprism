import AppKit
import Testing

@testable import Nightprism

@MainActor
struct OverlayStoreTests {
    private let suiteName = "NightprismTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    @Test
    func createsIndependentOverlaysAndPresentsTheirWindows() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let windows = TestWindows()
        let store = makeStore(windows: windows)

        store.addOverlay()
        store.addOverlay()

        #expect(store.overlays.count == 2)
        #expect(Set(store.overlays.map(\.id)).count == 2)
        #expect(store.overlays.allSatisfy { $0.opacity == 0.5 && !$0.locked })
        #expect(store.overlays.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        #expect(windows.controllers.count == 2)
        #expect(windows.controllers.values.allSatisfy { $0.showCount == 1 })
    }

    @Test
    func updatesWindowAndRestoresFrameOpacityAndLock() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let windows = TestWindows()
        let store = makeStore(windows: windows)
        store.addOverlay()
        var overlay = try #require(store.overlays.first)
        overlay.opacity = 0.73
        overlay.locked = true
        store.update(overlay)

        #expect(windows.controllers[overlay.id]?.lastApplied == overlay)

        let movedFrame = CGRect(x: -500, y: 150, width: 420, height: 270)
        store.handleFrameChange(id: overlay.id, frame: movedFrame)

        let restoredWindows = TestWindows()
        let restored = makeStore(windows: restoredWindows)
        let saved = try #require(restored.overlays.first)
        #expect(saved.id == overlay.id)
        #expect(saved.frame == movedFrame)
        #expect(saved.opacity == 0.73)
        #expect(saved.locked)
        #expect(restoredWindows.controllers[saved.id]?.showCount == 1)
    }

    @Test
    func removesOnlyRequestedOverlayAndPersistsDeletion() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let windows = TestWindows()
        let store = makeStore(windows: windows)
        store.addOverlay()
        store.addOverlay()
        let removed = try #require(store.overlays.first)
        let remaining = try #require(store.overlays.last)
        let removedWindow = try #require(windows.controllers[removed.id])

        store.remove(removed.id)

        #expect(removedWindow.closeCount == 1)
        #expect(store.overlays == [remaining])
        #expect(makeStore(windows: TestWindows()).overlays == [remaining])
    }

    @Test
    func ignoresUpdatesForUnknownOverlays() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let windows = TestWindows()
        let store = makeStore(windows: windows)
        let unknown = Overlay(frame: .zero, opacity: 0.9, locked: true)

        store.update(unknown)
        store.handleFrameChange(id: unknown.id, frame: CGRect(x: 0, y: 0, width: 10, height: 10))

        #expect(store.overlays.isEmpty)
        #expect(windows.controllers.isEmpty)
        #expect(defaults.data(forKey: "Nightprism.overlays.v1") == nil)
    }

    @Test
    func readsOriginalV1PersistenceFormat() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let id = UUID()
        let legacy = """
            [{"id":"\(id.uuidString)","x":10,"y":20,"w":600,"h":400,"opacity":0.35,"locked":true}]
            """
        defaults.set(Data(legacy.utf8), forKey: "Nightprism.overlays.v1")

        let restored = makeStore(windows: TestWindows())

        #expect(
            restored.overlays == [
                Overlay(
                    id: id, frame: CGRect(x: 10, y: 20, width: 600, height: 400), opacity: 0.35,
                    locked: true)
            ])
        #expect(restored.overlays.first?.warmth == 0)
        #expect(restored.overlays.first?.isEnabled == true)
    }

    @Test
    func handlesCorruptPersistenceWithoutOpeningWindows() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("invalid JSON".utf8), forKey: "Nightprism.overlays.v1")
        let windows = TestWindows()

        let store = makeStore(windows: windows)

        #expect(store.overlays.isEmpty)
        #expect(windows.controllers.isEmpty)
    }

    @Test
    func freeRectangleDefaultsToEnabledAndClickThrough() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(windows: TestWindows())

        store.addOverlay()

        let overlay = try #require(store.overlays.first)
        #expect(overlay.isEnabled)
        #expect(!overlay.isEditing)
        #expect(overlay.warmth == 0)
    }

    @Test
    func persistsWarmthAndEnabledStateForFreeRectangles() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(windows: TestWindows())
        store.addOverlay()
        let overlay = try #require(store.overlays.first)

        store.setWarmth(0.65, id: overlay.id)
        store.toggleEnabled(overlay.id)

        let restored = try #require(makeStore(windows: TestWindows()).overlays.first)
        #expect(restored.warmth == 0.65)
        #expect(!restored.isEnabled)
        #expect(!restored.isEditing)
    }

    @Test
    func neverRestoresAttachedTargetAsAFreeRectangle() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let store = makeStore(windows: TestWindows(), trackers: trackers)
        let target = makeTarget()

        store.addOverlay(target: target)
        store.addOverlay()

        let restored = makeStore(windows: TestWindows())
        #expect(restored.overlays.count == 1)
        #expect(restored.overlays.first?.target == nil)
        #expect(restored.overlays.first?.frame == store.overlays.last?.frame)
    }

    @Test
    func targetSnapshotScalesSavedCropProportionally() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let store = makeStore(windows: TestWindows(), trackers: trackers)
        let target = makeTarget(frame: CGRect(x: 100, y: 100, width: 100, height: 100))
        store.addOverlay(target: target)
        store.handleFrameChange(
            id: try #require(store.overlays.first).id,
            frame: CGRect(x: 125, y: 125, width: 50, height: 50)
        )

        try #require(trackers.trackers.first).emit(
            .visible(
                WindowSnapshot(
                    target: makeTarget(
                        id: target.id, ownerPID: target.ownerPID,
                        frame: CGRect(x: -50, y: 300, width: 200, height: 200)),
                    isOnScreen: true,
                    occluders: []
                ))
        )

        let overlay = try #require(store.overlays.first)
        #expect(overlay.crop == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(overlay.frame == CGRect(x: 0, y: 350, width: 100, height: 100))
    }

    @Test
    func occludersAreRemovedFromOverlayVisibleRects() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let store = makeStore(windows: TestWindows(), trackers: trackers)
        let target = makeTarget(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        store.addOverlay(target: target)
        try #require(trackers.trackers.first).emit(
            .visible(
                WindowSnapshot(
                    target: target,
                    isOnScreen: true,
                    occluders: [CGRect(x: 25, y: 25, width: 50, height: 50)]
                ))
        )

        let overlay = try #require(store.overlays.first)
        #expect(overlay.visibleRects?.count == 4)
        #expect(overlay.visibleRects?.reduce(0) { $0 + $1.width * $1.height } == 7500)
        #expect(overlay.shouldShow)
    }

    @Test
    func hiddenClosedAndUnavailableTargetsSuspendTheirOverlays() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let windows = TestWindows()
        let store = makeStore(windows: windows, trackers: trackers)
        store.addOverlay(target: makeTarget())
        let tracker = try #require(trackers.trackers.first)
        let overlayID = try #require(store.overlays.first).id

        for update: WindowTrackingUpdate in [.unavailable("no snapshot"), .hidden, .closed] {
            try #require(tracker.emit(update))
            let overlay = try #require(store.overlays.first)
            #expect(overlay.targetStatus != .ready)
            #expect(overlay.visibleRects?.isEmpty == true)
            #expect(!overlay.shouldShow)
            #expect(windows.controllers[overlayID]?.lastApplied?.shouldShow == false)
        }
        #expect(tracker.stopCount >= 1)
    }

    @Test
    func trackingUpdatesCannotReenableOverlayDuringGlobalPause() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let windows = TestWindows()
        let store = makeStore(windows: windows, trackers: trackers)
        let target = makeTarget()
        store.addOverlay(target: target)
        let tracker = try #require(trackers.trackers.first)
        try #require(
            tracker.emit(.visible(WindowSnapshot(target: target, isOnScreen: true, occluders: []))))

        store.togglePause()
        let movedTarget = makeTarget(
            id: target.id, ownerPID: target.ownerPID,
            frame: CGRect(x: 30, y: 40, width: 120, height: 120))
        try #require(
            tracker.emit(
                .visible(WindowSnapshot(target: movedTarget, isOnScreen: true, occluders: []))))

        let overlay = try #require(store.overlays.first)
        #expect(store.isPaused)
        #expect(overlay.isEnabled)
        #expect(overlay.frame == movedTarget.frame)
        #expect(windows.controllers[overlay.id]?.lastApplied?.isEnabled == false)
        #expect(windows.controllers[overlay.id]?.lastApplied?.shouldShow == false)
    }

    @Test
    func lockingExitsEditing() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(windows: TestWindows())
        store.addOverlay()
        let id = try #require(store.overlays.first).id
        store.toggleEditing(id)

        store.toggleLock(id)

        let overlay = try #require(store.overlays.first)
        #expect(overlay.locked)
        #expect(!overlay.isEditing)
    }

    @Test
    func resetCropDoesNothingWhileLocked() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let store = makeStore(windows: TestWindows(), trackers: trackers)
        let target = makeTarget(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        store.addOverlay(target: target)
        let id = try #require(store.overlays.first).id
        store.handleFrameChange(id: id, frame: CGRect(x: 20, y: 30, width: 40, height: 50))
        store.toggleLock(id)
        let before = try #require(store.overlays.first)

        store.resetCrop(id)

        let after = try #require(store.overlays.first)
        #expect(after.crop == before.crop)
        #expect(after.frame == before.frame)
        #expect(after.locked)
    }

    @Test
    func lateSnapshotCannotResurrectClosedTarget() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let trackers = TestTrackers()
        let store = makeStore(windows: TestWindows(), trackers: trackers)
        let target = makeTarget()
        store.addOverlay(target: target)
        let tracker = try #require(trackers.trackers.first)
        let callback = try #require(tracker.onUpdate)
        callback(.closed)

        callback(.visible(WindowSnapshot(target: target, isOnScreen: true, occluders: [])))

        #expect(store.overlays.first?.targetStatus == .closed)
        #expect(store.overlays.first?.shouldShow == false)
    }

    private func makeStore(windows: TestWindows, trackers: TestTrackers? = nil) -> OverlayStore {
        OverlayStore(
            defaults: defaults,
            trackerFactory: { trackers?.makeTracker() ?? TestWindowTracker() },
            controllerFactory: { overlay, _ in
                let controller = TestWindow()
                windows.controllers[overlay.id] = controller
                return controller
            }
        )
    }

    private func makeTarget(
        id: CGWindowID = 42, ownerPID: pid_t = 123,
        frame: CGRect = CGRect(x: 10, y: 20, width: 100, height: 100)
    ) -> WindowTarget {
        WindowTarget(
            id: id, ownerPID: ownerPID, appName: "Example", title: "Document", frame: frame)
    }
}

@MainActor
private final class TestWindows {
    var controllers: [Overlay.ID: TestWindow] = [:]
}

@MainActor
private final class TestWindow: OverlayWindowControlling {
    private(set) var showCount = 0
    private(set) var closeCount = 0
    private(set) var lastApplied: Overlay?

    func showWindow(_ sender: Any?) { showCount += 1 }
    func close() { closeCount += 1 }
    func apply(_ overlay: Overlay) { lastApplied = overlay }
}

@MainActor
private final class TestTrackers {
    private(set) var trackers: [TestWindowTracker] = []

    func makeTracker() -> TestWindowTracker {
        let tracker = TestWindowTracker()
        trackers.append(tracker)
        return tracker
    }
}

@MainActor
private final class TestWindowTracker: WindowTracking {
    private(set) var onUpdate: (@MainActor @Sendable (WindowTrackingUpdate) -> Void)?
    private(set) var stopCount = 0

    func start(
        target: WindowTarget,
        onUpdate: @escaping @MainActor @Sendable (WindowTrackingUpdate) -> Void
    ) {
        self.onUpdate = onUpdate
    }

    func stop() {
        stopCount += 1
        onUpdate = nil
    }

    @discardableResult
    func emit(_ update: WindowTrackingUpdate) -> Bool {
        guard let onUpdate else { return false }
        onUpdate(update)
        return true
    }
}
