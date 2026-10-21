import AppKit
import Observation

@MainActor
protocol OverlayWindowControlling: AnyObject {
    func showWindow(_ sender: Any?)
    func close()
    func apply(_ overlay: Overlay)
}

@Observable
@MainActor
final class OverlayStore {
    private(set) var overlays: [Overlay] = []
    private(set) var isPaused = false
    @ObservationIgnored private var controllers: [Overlay.ID: any OverlayWindowControlling] = [:]
    @ObservationIgnored private var trackers: [Overlay.ID: any WindowTracking] = [:]
    @ObservationIgnored private var occluders: [Overlay.ID: [CGRect]] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let trackerFactory: @MainActor () -> any WindowTracking
    @ObservationIgnored private let controllerFactory:
        @MainActor (Overlay, OverlayStore) -> any OverlayWindowControlling

    private let persistenceKey = "Nightprism.overlays.v1"

    init(
        defaults: UserDefaults = .standard,
        trackerFactory: @escaping @MainActor () -> any WindowTracking = { WindowTracker() },
        controllerFactory:
            @escaping @MainActor (Overlay, OverlayStore) -> any OverlayWindowControlling = {
                OverlayWindowController(overlay: $0, store: $1)
            }
    ) {
        self.defaults = defaults
        self.trackerFactory = trackerFactory
        self.controllerFactory = controllerFactory
        load()
    }

    func addOverlay(target: WindowTarget? = nil) {
        let screenFrame =
            NSScreen.main?.visibleFrame ?? CGRect(x: 200, y: 200, width: 800, height: 600)
        let size = CGSize(
            width: min(600, screenFrame.width * 0.4), height: min(400, screenFrame.height * 0.4))
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)
        let overlay = Overlay(
            frame: target?.frame ?? CGRect(origin: origin, size: size),
            opacity: 0.5, locked: false, target: target)
        overlays.append(overlay)
        present(overlay)
        if let target {
            let tracker = trackerFactory()
            trackers[overlay.id] = tracker
            tracker.start(target: target) { [weak self] update in
                self?.handleTrackingUpdate(id: overlay.id, update: update)
            }
        }
        persist()
    }

    func remove(_ id: Overlay.ID) {
        trackers.removeValue(forKey: id)?.stop()
        occluders[id] = nil
        controllers.removeValue(forKey: id)?.close()
        overlays.removeAll { $0.id == id }
        persist()
    }

    func update(_ overlay: Overlay) {
        guard let idx = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        var updated = overlay
        updated.opacity = Self.clamp(updated.opacity, fallback: 0.5)
        updated.warmth = Self.clamp(updated.warmth, fallback: 0)
        if updated.locked || !updated.isEnabled { updated.isEditing = false }
        overlays[idx] = updated
        apply(updated)
        persist()
    }

    func setOpacity(_ value: Double, id: Overlay.ID) {
        modify(id) { $0.opacity = value }
    }

    func setWarmth(_ value: Double, id: Overlay.ID) {
        modify(id) { $0.warmth = value }
    }

    func toggleLock(_ id: Overlay.ID) {
        modify(id) { $0.locked.toggle() }
    }

    func toggleEditing(_ id: Overlay.ID) {
        modify(id) {
            guard !$0.locked, $0.isEnabled else { return }
            $0.isEditing.toggle()
        }
    }

    func toggleEnabled(_ id: Overlay.ID) {
        modify(id) { $0.isEnabled.toggle() }
    }

    func togglePause() {
        isPaused.toggle()
        for overlay in overlays { apply(overlay) }
    }

    func resetCrop(_ id: Overlay.ID) {
        guard let idx = overlays.firstIndex(where: { $0.id == id }),
            let target = overlays[idx].target, !overlays[idx].locked
        else { return }
        overlays[idx].crop = WindowGeometry.fullCrop
        overlays[idx].frame = target.frame
        refreshVisibleRects(at: idx)
        apply(overlays[idx])
    }

    func handleFrameChange(id: Overlay.ID, frame: CGRect) {
        guard let idx = overlays.firstIndex(where: { $0.id == id }) else { return }
        if let target = overlays[idx].target {
            guard let crop = WindowGeometry.normalizedCrop(frame, in: target.frame) else {
                apply(overlays[idx])
                return
            }
            overlays[idx].crop = crop
            overlays[idx].frame = WindowGeometry.cropFrame(crop, in: target.frame)
            refreshVisibleRects(at: idx)
            apply(overlays[idx])
        } else {
            overlays[idx].frame = frame
            persist()
        }
    }

    private func modify(_ id: Overlay.ID, _ change: (inout Overlay) -> Void) {
        guard var overlay = overlays.first(where: { $0.id == id }) else { return }
        change(&overlay)
        update(overlay)
    }

    private func handleTrackingUpdate(id: Overlay.ID, update: WindowTrackingUpdate) {
        guard let idx = overlays.firstIndex(where: { $0.id == id }),
            let target = overlays[idx].target, overlays[idx].targetStatus != .closed
        else { return }
        let previous = overlays[idx]
        switch update {
        case .visible(let snapshot):
            guard snapshot.target.id == target.id, snapshot.target.ownerPID == target.ownerPID
            else { return }
            overlays[idx].target = snapshot.target
            overlays[idx].targetStatus = snapshot.isOnScreen ? .ready : .hidden
            overlays[idx].frame = WindowGeometry.cropFrame(
                overlays[idx].crop, in: snapshot.target.frame)
            occluders[id] = snapshot.occluders
            refreshVisibleRects(at: idx)
        case .hidden:
            overlays[idx].targetStatus = .hidden
            overlays[idx].visibleRects = []
        case .closed:
            overlays[idx].targetStatus = .closed
            overlays[idx].visibleRects = []
            trackers.removeValue(forKey: id)?.stop()
        case .unavailable:
            overlays[idx].targetStatus = .unavailable
            overlays[idx].visibleRects = []
        }
        if overlays[idx] != previous { apply(overlays[idx]) }
    }

    private func refreshVisibleRects(at idx: Int) {
        let overlay = overlays[idx]
        overlays[idx].visibleRects =
            overlay.targetStatus == .ready
            ? WindowVisibility.visibleRects(
                in: overlay.frame, occludedBy: occluders[overlay.id] ?? [])
            : []
    }

    private func present(_ overlay: Overlay) {
        var displayed = overlay
        if isPaused { displayed.isEnabled = false }
        controllers[overlay.id] = controllerFactory(displayed, self)
        if displayed.shouldShow { controllers[overlay.id]?.showWindow(nil) }
    }

    private func apply(_ overlay: Overlay) {
        var displayed = overlay
        if isPaused { displayed.isEnabled = false }
        controllers[overlay.id]?.apply(displayed)
    }

    private func persist() {
        // Foreign window IDs are only valid for this session. Never restore an attached overlay
        // as an unbound rectangle over whichever app happens to occupy its old coordinates.
        let payload = overlays.filter { $0.target == nil }.map { OverlayDTO(from: $0) }
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: persistenceKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: persistenceKey),
            let payload = try? JSONDecoder().decode([OverlayDTO].self, from: data)
        else { return }
        overlays = payload.map { $0.toOverlay() }
        for overlay in overlays { present(overlay) }
    }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : fallback
    }
}

enum OverlayTargetStatus: Hashable {
    case ready, hidden, closed, unavailable
}

struct Overlay: Identifiable, Hashable {
    let id: UUID
    var frame: CGRect
    var opacity: Double
    var locked: Bool
    var warmth: Double
    var isEnabled: Bool
    var isEditing = false
    var target: WindowTarget?
    var crop = WindowGeometry.fullCrop
    var targetStatus: OverlayTargetStatus
    var visibleRects: [CGRect]?

    var shouldShow: Bool {
        isEnabled && (target == nil || targetStatus == .ready) && visibleRects?.isEmpty != true
    }

    init(
        id: UUID = UUID(), frame: CGRect, opacity: Double, locked: Bool,
        warmth: Double = 0, isEnabled: Bool = true, target: WindowTarget? = nil
    ) {
        self.id = id
        self.frame = frame
        self.opacity = opacity.isFinite ? max(0, min(1, opacity)) : 0.5
        self.locked = locked
        self.warmth = warmth.isFinite ? max(0, min(1, warmth)) : 0
        self.isEnabled = isEnabled
        self.target = target
        self.targetStatus = target == nil ? .ready : .hidden
    }
}

private struct OverlayDTO: Codable {
    var id: UUID
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var opacity: Double
    var locked: Bool
    var warmth: Double?
    var enabled: Bool?

    init(from overlay: Overlay) {
        id = overlay.id
        x = overlay.frame.minX
        y = overlay.frame.minY
        w = overlay.frame.width
        h = overlay.frame.height
        opacity = overlay.opacity
        locked = overlay.locked
        warmth = overlay.warmth
        enabled = overlay.isEnabled
    }

    func toOverlay() -> Overlay {
        Overlay(
            id: id, frame: CGRect(x: x, y: y, width: w, height: h), opacity: opacity,
            locked: locked, warmth: warmth ?? 0, isEnabled: enabled ?? true)
    }
}
