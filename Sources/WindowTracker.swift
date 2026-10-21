import AppKit
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit

struct WindowSnapshot: Sendable {
    let target: WindowTarget
    let isOnScreen: Bool
    let occluders: [CGRect]
}

enum WindowTrackingUpdate: Sendable {
    case visible(WindowSnapshot)
    case hidden
    case closed
    case unavailable(String)
}

@MainActor
protocol WindowTracking: AnyObject {
    func start(
        target: WindowTarget,
        onUpdate: @escaping @MainActor @Sendable (WindowTrackingUpdate) -> Void
    )
    func stop()
}

protocol WindowSnapshotProviding: Sendable {
    func snapshot(for target: WindowTarget, primaryScreenHeight: CGFloat) async
        -> WindowTrackingUpdate
}

actor SystemWindowSnapshotProvider: WindowSnapshotProviding {
    func snapshot(for target: WindowTarget, primaryScreenHeight: CGFloat) async
        -> WindowTrackingUpdate
    {
        guard primaryScreenHeight.isFinite, primaryScreenHeight > 0 else {
            return .unavailable("The primary display geometry is unavailable.")
        }

        guard let targetInfo = windowInfo(for: target.id, options: .optionIncludingWindow) else {
            return .unavailable("Window Server did not return window metadata.")
        }
        guard let targetRow = targetInfo.first(where: { windowID($0) == target.id }),
            ownerPID(targetRow) == target.ownerPID
        else {
            return .closed
        }
        guard let targetBounds = bounds(targetRow) else {
            return .unavailable("The selected window has invalid geometry.")
        }
        guard isOnScreen(targetRow), alpha(targetRow) > 0 else { return .hidden }

        guard let aboveInfo = windowInfo(for: target.id, options: .optionOnScreenAboveWindow) else {
            return .unavailable("Window Server did not return window ordering metadata.")
        }

        let occluders = aboveInfo.compactMap { row -> CGRect? in
            // Overlay panels must not mask themselves. Our normal controls window still
            // covers the target and must participate in occlusion like any other window.
            let isOwnOverlay =
                ownerPID(row) == getpid()
                && (row[kCGWindowLayer as String] as? NSNumber)?.intValue
                    == Int(CGWindowLevelForKey(.floatingWindow))
            guard !isOwnOverlay, alpha(row) > 0,
                let quartzBounds = bounds(row)
            else { return nil }
            let frame = WindowGeometry.appKitRect(
                from: quartzBounds, primaryScreenHeight: primaryScreenHeight)
            return isValid(frame) ? frame : nil
        }

        let frame = WindowGeometry.appKitRect(
            from: targetBounds, primaryScreenHeight: primaryScreenHeight)
        guard isValid(frame) else {
            return .unavailable("The selected window has invalid geometry.")
        }
        return .visible(
            WindowSnapshot(
                target: WindowTarget(
                    id: target.id,
                    ownerPID: target.ownerPID,
                    appName: target.appName,
                    title: target.title,
                    frame: frame
                ),
                isOnScreen: true,
                occluders: occluders
            ))
    }

    private func windowInfo(for id: CGWindowID, options: CGWindowListOption)
        -> [[String: Any]]?
    {
        guard let info = CGWindowListCopyWindowInfo(options, id) else { return nil }
        return info as? [[String: Any]]
    }

    private func windowID(_ row: [String: Any]) -> CGWindowID? {
        (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    private func ownerPID(_ row: [String: Any]) -> pid_t? {
        (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    private func alpha(_ row: [String: Any]) -> CGFloat {
        (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    }

    private func isOnScreen(_ row: [String: Any]) -> Bool {
        (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    }

    private func bounds(_ row: [String: Any]) -> CGRect? {
        guard let dictionary = row[kCGWindowBounds as String] as? [String: Any] else { return nil }
        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &rect),
            isValid(rect)
        else {
            return nil
        }
        return rect
    }

    private func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite && rect.width.isFinite
            && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}

@MainActor
final class WindowTracker: WindowTracking {
    private let provider: any WindowSnapshotProviding
    private let interval: Duration
    private let primaryScreenHeight: @MainActor @Sendable () -> CGFloat
    private var pollTask: Task<Void, Never>?
    private var generation = UUID()

    init(
        provider: any WindowSnapshotProviding = SystemWindowSnapshotProvider(),
        interval: Duration = .milliseconds(100),
        primaryScreenHeight: @escaping @MainActor @Sendable () -> CGFloat = {
            NSScreen.screens.first?.frame.maxY ?? 0
        }
    ) {
        self.provider = provider
        self.interval = interval
        self.primaryScreenHeight = primaryScreenHeight
    }

    func start(
        target: WindowTarget,
        onUpdate: @escaping @MainActor @Sendable (WindowTrackingUpdate) -> Void
    ) {
        stop()
        let currentGeneration = generation
        let provider = self.provider
        let interval = self.interval
        let screenHeightProvider = self.primaryScreenHeight

        pollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                let height = await screenHeightProvider()
                let update = await provider.snapshot(for: target, primaryScreenHeight: height)
                guard !Task.isCancelled else { return }

                let shouldContinue = await MainActor.run { [weak self] in
                    guard let self, self.generation == currentGeneration else { return false }
                    onUpdate(update)
                    if case .closed = update {
                        self.stop()
                        return false
                    }
                    return true
                }
                guard shouldContinue else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        pollTask?.cancel()
        pollTask = nil
    }

    @MainActor
    static func availableWindows() async throws -> [WindowTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true)
        let primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        guard primaryScreenHeight.isFinite, primaryScreenHeight > 0 else { return [] }

        return content.windows.compactMap { window in
            guard window.windowID != 0,
                window.windowLayer == Int(CGWindowLevelForKey(.normalWindow)),
                let application = window.owningApplication,
                application.processID != getpid(),
                let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else { return nil }
            let appName = application.applicationName.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let name = appName.isEmpty ? application.bundleIdentifier : appName
            let frame = WindowGeometry.appKitRect(
                from: window.frame, primaryScreenHeight: primaryScreenHeight)
            guard frame.width > 0, frame.height > 0 else { return nil }
            return WindowTarget(
                id: window.windowID,
                ownerPID: application.processID,
                appName: name,
                title: title,
                frame: frame
            )
        }
    }
}
