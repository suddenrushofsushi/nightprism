import CoreGraphics
import Foundation
import Testing

@testable import Nightprism

@MainActor
struct WindowTrackerTests {
    @Test
    func deliversVisibleSnapshot() async throws {
        let target = makeTarget(id: 41)
        let snapshot = WindowSnapshot(
            target: target, isOnScreen: true,
            occluders: [CGRect(x: 5, y: 6, width: 70, height: 80)])
        try await expectUpdate(.visible(snapshot), target: target)
    }

    @Test
    func deliversHiddenUpdate() async throws {
        try await expectUpdate(.hidden, target: makeTarget(id: 42))
    }

    @Test
    func deliversClosedUpdateAndStops() async throws {
        let provider = ControlledWindowProvider()
        let tracker = WindowTracker(provider: provider, interval: .seconds(30))
        defer { tracker.stop() }
        let collector = UpdateCollector()
        tracker.start(target: makeTarget(id: 43)) { collector.yield($0) }

        #expect(await provider.waitForRequest(1))
        await provider.respond(to: 1, with: .closed)

        guard case .closed? = await collector.nextUpdate() else {
            Issue.record("Expected the closed update")
            return
        }
        #expect(await provider.requestCount == 1)
    }

    @Test
    func deliversUnavailableUpdate() async throws {
        try await expectUpdate(
            .unavailable("Window Server unavailable"), target: makeTarget(id: 44))
    }

    @Test
    func restartDiscardsPendingResultFromPreviousTarget() async throws {
        let provider = ControlledWindowProvider()
        let tracker = WindowTracker(provider: provider, interval: .seconds(30))
        let firstTarget = makeTarget(id: 45)
        let secondTarget = makeTarget(id: 46)
        let collector = UpdateCollector()
        defer { tracker.stop() }
        tracker.start(target: firstTarget) { collector.yield($0) }

        #expect(await provider.waitForRequest(1))
        tracker.start(target: secondTarget) { collector.yield($0) }
        #expect(await provider.waitForRequest(2))

        let staleSnapshot = WindowSnapshot(target: firstTarget, isOnScreen: true, occluders: [])
        await provider.respond(to: 1, with: .visible(staleSnapshot))
        let currentSnapshot = WindowSnapshot(target: secondTarget, isOnScreen: true, occluders: [])
        await provider.respond(to: 2, with: .visible(currentSnapshot))

        guard case .visible(let delivered)? = await collector.nextUpdate() else {
            Issue.record("Expected the current target snapshot")
            return
        }
        #expect(delivered.target.id == secondTarget.id)
    }

    @Test
    func stopDiscardsPendingResult() async {
        let provider = ControlledWindowProvider()
        let tracker = WindowTracker(provider: provider, interval: .seconds(30))
        let target = makeTarget(id: 47)
        let collector = UpdateCollector()
        defer { tracker.stop() }
        tracker.start(target: target) { collector.yield($0) }

        #expect(await provider.waitForRequest(1))
        tracker.stop()
        await provider.respond(
            to: 1,
            with: .visible(WindowSnapshot(target: target, isOnScreen: true, occluders: [])))

        #expect(await collector.nextUpdate() == nil)
    }

    private func expectUpdate(_ expected: WindowTrackingUpdate, target: WindowTarget) async throws {
        let provider = ControlledWindowProvider()
        let tracker = WindowTracker(provider: provider, interval: .seconds(30))
        let collector = UpdateCollector()
        defer { tracker.stop() }
        tracker.start(target: target) { collector.yield($0) }
        #expect(await provider.waitForRequest(1))
        await provider.respond(to: 1, with: expected)
        let delivered = await collector.nextUpdate()
        #expect(updatesEqual(delivered, expected))
    }

    private func updatesEqual(_ lhs: WindowTrackingUpdate?, _ rhs: WindowTrackingUpdate) -> Bool {
        switch (lhs, rhs) {
        case (.hidden, .hidden), (.closed, .closed):
            true
        case (.unavailable(let left), .unavailable(let right)):
            left == right
        case (.visible(let left), .visible(let right)):
            left.target == right.target && left.isOnScreen == right.isOnScreen
                && left.occluders == right.occluders
        default:
            false
        }
    }

    private func makeTarget(id: CGWindowID) -> WindowTarget {
        WindowTarget(
            id: id, ownerPID: 123, appName: "Zoom", title: "Meeting",
            frame: CGRect(x: 10, y: 20, width: 800, height: 600))
    }
}

@MainActor
private final class UpdateCollector {
    private var waiting: (UUID, CheckedContinuation<WindowTrackingUpdate?, Never>)?
    private var timeoutTask: Task<Void, Never>?
    private var buffered: [WindowTrackingUpdate] = []
    private(set) var count = 0

    func nextUpdate(timeout: Duration = .seconds(2)) async -> WindowTrackingUpdate? {
        if !buffered.isEmpty { return buffered.removeFirst() }
        return await withCheckedContinuation { continuation in
            let id = UUID()
            waiting = (id, continuation)
            timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.expireWaiter(id)
            }
        }
    }

    func yield(_ update: WindowTrackingUpdate) {
        count += 1
        guard let (_, continuation) = waiting else {
            buffered.append(update)
            return
        }
        waiting = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: update)
    }

    private func expireWaiter(_ id: UUID) {
        guard let (waitingID, continuation) = waiting, waitingID == id else { return }
        waiting = nil
        timeoutTask = nil
        continuation.resume(returning: nil)
    }
}

private actor ControlledWindowProvider: WindowSnapshotProviding {
    private var requests = 0
    private var pending: [Int: CheckedContinuation<WindowTrackingUpdate, Never>] = [:]
    private var requestWaiters: [(UUID, Int, CheckedContinuation<Bool, Never>)] = []

    var requestCount: Int { requests }

    func snapshot(for target: WindowTarget, primaryScreenHeight: CGFloat) async
        -> WindowTrackingUpdate
    {
        requests += 1
        let request = requests
        resumeSatisfied(&requestWaiters, through: request)
        return await withCheckedContinuation { pending[request] = $0 }
    }

    func waitForRequest(_ count: Int, timeout: Duration = .seconds(2)) async -> Bool {
        guard requests < count else { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            requestWaiters.append((id, count, continuation))
            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self.expireRequestWaiter(id)
            }
        }
    }

    func respond(to request: Int, with update: WindowTrackingUpdate) {
        pending.removeValue(forKey: request)?.resume(returning: update)
    }

    private func resumeSatisfied(
        _ waiters: inout [(UUID, Int, CheckedContinuation<Bool, Never>)], through value: Int
    ) {
        let ready = waiters.filter { $0.1 <= value }
        waiters.removeAll { $0.1 <= value }
        for (_, _, continuation) in ready {
            continuation.resume(returning: true)
        }
    }

    private func expireRequestWaiter(_ id: UUID) {
        guard let index = requestWaiters.firstIndex(where: { $0.0 == id }) else { return }
        let (_, _, continuation) = requestWaiters.remove(at: index)
        continuation.resume(returning: false)
    }
}
