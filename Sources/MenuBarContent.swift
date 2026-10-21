import CoreGraphics
import SwiftUI

struct MenuBarContent: View {
    @Bindable var store: OverlayStore
    var showsOpenControls = true
    @Environment(\.openWindow) private var openWindow
    @State private var showsWindowPicker = false
    @State private var windows: [WindowTarget] = []
    @State private var isLoading = false
    @State private var needsWindowAccess = false
    @State private var windowError: String?
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nightprism").font(.headline)
                Spacer()
                Button(store.isPaused ? "Resume all" : "Pause all") { store.togglePause() }
                    .disabled(store.overlays.isEmpty)
            }

            HStack {
                Button("Choose Window", systemImage: "macwindow") {
                    showsWindowPicker.toggle()
                    if showsWindowPicker { Task { await refreshWindows() } }
                }
                Button("New Rectangle", systemImage: "plus.rectangle") { store.addOverlay() }
            }

            if showsWindowPicker { windowPicker }

            Divider()

            if store.overlays.isEmpty {
                Text("Choose a Zoom or Safari window, or add a rectangle.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.overlays) { overlay in
                            OverlayRow(overlay: overlay, store: store)
                        }
                    }
                }
                .frame(height: min(400, CGFloat(store.overlays.count) * 220))
            }

            Divider()
            HStack {
                if showsOpenControls {
                    Button("Open Controls") {
                        openWindow(id: "controls")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .keyboardShortcut(",")
                }
                Spacer()
                Button("Quit Nightprism") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 390)
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if needsWindowAccess {
                Text(
                    "Allow Screen Recording access so Nightprism can find your windows. This prototype does not record images."
                )
                .font(.callout)
                Button("Allow Window Access") {
                    _ = CGRequestScreenCaptureAccess()
                    Task { await refreshWindows() }
                }
                Text("After allowing access in System Settings, refresh or relaunch Nightprism.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Filter windows", text: $search)
                Button("Refresh") { Task { await refreshWindows() } }
                    .disabled(isLoading)
            }
            if isLoading {
                ProgressView().controlSize(.small)
            } else if let windowError {
                Text(windowError).font(.callout).foregroundStyle(.secondary)
            } else if !needsWindowAccess {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredWindows) { target in
                            Button {
                                store.addOverlay(target: target)
                                showsWindowPicker = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.appName).font(.caption).foregroundStyle(.secondary)
                                    Text(target.title).lineLimit(1).truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                        if filteredWindows.isEmpty {
                            Text("No matching windows. Open Zoom or Safari, then refresh.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var filteredWindows: [WindowTarget] {
        windows.filter {
            search.isEmpty || $0.appName.localizedCaseInsensitiveContains(search)
                || $0.title.localizedCaseInsensitiveContains(search)
        }
    }

    @MainActor
    private func refreshWindows() async {
        guard !isLoading else { return }
        needsWindowAccess = !CGPreflightScreenCaptureAccess()
        guard !needsWindowAccess else {
            windows = []
            windowError = nil
            return
        }
        isLoading = true
        windowError = nil
        defer { isLoading = false }
        do {
            windows = try await WindowTracker.availableWindows().sorted {
                $0.appName.localizedStandardCompare($1.appName) == .orderedSame
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.appName.localizedStandardCompare($1.appName) == .orderedAscending
            }
        } catch {
            windowError = "Could not list windows. Check Screen Recording access and try again."
        }
    }
}

private struct OverlayRow: View {
    let overlay: Overlay
    let store: OverlayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(overlay.target?.appName ?? "Rectangle").font(.headline)
                    Text(overlay.target?.title ?? String(overlay.id.uuidString.prefix(8)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    store.toggleEnabled(overlay.id)
                } label: {
                    Image(systemName: overlay.isEnabled ? "power.circle.fill" : "power.circle")
                }
                .help(overlay.isEnabled ? "Disable overlay" : "Enable overlay")
                Button(role: .destructive) {
                    store.remove(overlay.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete overlay")
            }
            HStack {
                Button(overlay.isEditing ? "Done Editing" : "Edit Rectangle") {
                    store.toggleEditing(overlay.id)
                }
                .disabled(overlay.locked || !overlay.isEnabled || store.isPaused)
                Button(
                    overlay.locked ? "Unlock" : "Lock",
                    systemImage: overlay.locked ? "lock.fill" : "lock.open"
                ) {
                    store.toggleLock(overlay.id)
                }
                if overlay.target != nil {
                    Button("Fit Window") { store.resetCrop(overlay.id) }
                        .disabled(overlay.locked)
                }
            }
            if overlay.isEditing {
                Text("Drag the rectangle or its edges, then choose Done Editing.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Dim").frame(width: 48, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { overlay.opacity }, set: { store.setOpacity($0, id: overlay.id) }),
                    in: 0...1
                )
                .accessibilityLabel("Dimming")
                Text("\(Int(overlay.opacity * 100))%")
                    .monospacedDigit().frame(width: 36, alignment: .trailing)
            }
            HStack {
                Text("Warmth").frame(width: 48, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { overlay.warmth }, set: { store.setWarmth($0, id: overlay.id) }),
                    in: 0...1
                )
                .accessibilityLabel("Warmth")
                Text("\(Int(overlay.warmth * 100))%")
                    .monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var status: String {
        if store.isPaused { return "All overlays paused" }
        if !overlay.isEnabled { return "Overlay disabled" }
        switch overlay.targetStatus {
        case .hidden: return "Target window hidden"
        case .closed: return "Target window closed — choose a window again"
        case .unavailable: return "Window tracking paused — waiting for window information"
        case .ready:
            return "Clicks pass through\(overlay.locked ? "; position and size locked" : "")"
        }
    }
}
