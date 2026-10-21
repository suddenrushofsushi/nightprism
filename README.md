# Nightprism

A macOS menu bar app for dimming selected parts of your screen with translucent overlays.

Nightprism is an early personal project for toning down bright content during Zoom screen sharing.
The manual prototype supports black dimming and a warm tint; Safari in light mode is the first
effect-comparison target. Product direction is tracked in
[GitHub issues](https://github.com/suddenrushofsushi/nightprism/issues).

## Current behavior

- Choose a specific Zoom, Safari, or other app window, or create a free-standing rectangle.
- Follow a selected window, including when it stays visible behind another active app.
- Crop the overlay; the crop scales proportionally when its target is resized.
- Exclude rectangular regions covered by other windows; hide when the target is hidden or closed.
- Adjust dimming and warmth; pause all overlays or disable one immediately.
- Click through by default. Enter **Edit Rectangle** to move/resize; locking prevents both.
- Restore free-standing rectangles and their appearance settings across launches.

Window attachments last for the current app session. Reselect the target after restarting rather
than restoring stale window IDs over unrelated content. Free-standing rectangles are still restored
at their saved coordinates; display-disconnection recovery remains unfinished.

Occlusion uses conservative rectangular window bounds. Translucent/irregular windows and shadows
can leave more of the target untinted. Following and clipping update from periodic window metadata,
so they can briefly lag behind movement; this is not a guarantee against every bright frame.

## Requirements

- **App deployment target:** macOS 14 or newer. Older supported systems have not yet been tested.
- **Development:** Xcode 27.1 with its bundled Swift 6.4 compiler, using Swift 6 language mode.
  Use a macOS version supported by that Xcode release.
- **Project generation:** [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).
- **Shader compilation:** the optional Xcode Metal Toolchain component must be installed to build.

There are no third-party runtime dependencies. Choosing a foreign window requires Screen Recording
access so ScreenCaptureKit can list its title and identity. This prototype reads window metadata;
it does not start a capture stream, record images, or upload screen content. Free-standing rectangles
work without that permission.
Local ad hoc rebuilds can invalidate a previous grant; reauthorize the current build in System Settings
and relaunch if the chooser still requests access after a rebuild.

## Build and run

Install Xcode and XcodeGen first. For a new Xcode installation, run these commands yourself to
select Xcode, review its license, and install required components:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
```

Then install the Metal compiler and generate the project:

```sh
xcodebuild -downloadComponent metalToolchain
xcodegen generate
open Nightprism.xcodeproj
```

Run the `Nightprism` scheme in Xcode. The app has a moon icon in the menu bar and no Dock icon.
Controls open in a normal window at launch, so they stay available while working in Safari or Zoom.
Close that window to keep only the menu bar controls; **Open Controls** in the moon menu reopens it.

1. Click **Choose Window**. Grant window access when requested, then refresh or relaunch if needed.
2. Select the Safari light-mode window or a Zoom meeting window. The overlay starts click-through.
3. Adjust **Dim** and **Warmth** to compare the effects.
4. Choose **Edit Rectangle** to crop to shared content, then **Done Editing**. **Fit Window** resets the crop.
5. **Lock** prevents manual position and size changes while following continues.
6. Use **Pause all**, a row's power button, or delete to remove the effect immediately.

For an unattached region, use **New Rectangle** and enter editing mode to position it.

For a command-line development build:

```sh
xcodebuild -project Nightprism.xcodeproj \
  -scheme Nightprism -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/local build
open .build/local/Build/Products/Debug/Nightprism.app
```

The project uses local ad hoc signing. Signed and notarized distribution builds are not set up;
there are no downloadable releases yet.

## Checks

```sh
swift format lint --strict --recursive Sources Tests
xcodebuild -project Nightprism.xcodeproj \
  -scheme Nightprism -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/local \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Nightprism.xcodeproj \
  -scheme Nightprism -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/local \
  CODE_SIGNING_ALLOWED=NO build
```

Swift Testing covers state/persistence compatibility, crop and monitor geometry, occlusion subtraction,
tracking lifecycle, and window input/locking behavior. State tests use isolated preferences and fake
trackers. Controller tests briefly create real panels; they do not replace interactive testing of GPU
output or foreign app behavior. The test runner hosts the app and may appear in the menu bar.

CI runs these checks with Xcode 27.1 on GitHub's `xcode-27` runner. That runner image is currently
in public preview, so availability may change. Workflow actions and XcodeGen downloads are pinned.

## Code map

- `Sources/NightprismApp.swift`: app entry point and menu bar scene.
- `Sources/MenuBarContent.swift`: per-overlay controls.
- `Sources/OverlayStore.swift`: observable state, controller ownership, and versioned preferences.
- `Sources/OverlayWindowController.swift`: AppKit panels, window behavior, and frame updates.
- `Sources/MetalTintView.swift`: on-demand Metal drawing and drawable sizing.
- `Sources/Shaders.metal`: full-screen triangle and premultiplied-alpha tint shader.
- `Sources/WindowTarget.swift`: target identity, coordinate conversion, and crop geometry.
- `Sources/WindowVisibility.swift`: nonoverlapping visible regions after rectangle subtraction.
- `Sources/WindowTracker.swift`: explicit window enumeration and background metadata polling.
- `Tests/`: state, persistence, geometry, clipping, tracking, and controller regression tests.

`project.yml` is the source of truth for build settings, targets, metadata, and entitlements.
Regenerate after changing it. Generated Xcode projects and build products are ignored by Git.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development conventions and manual smoke checks.
Report bugs and discuss proposed features in [issues](https://github.com/suddenrushofsushi/nightprism/issues).
Automatic bright-share detection, suspend/resume on content changes, and launch at login are later
work. Pre-arm the selected Zoom window for the manual workflow; a reactive detector cannot prevent
a bright frame it has not yet observed. Inversion and XOR effects are outside the current scope.

Nightprism is licensed under the [MIT License](LICENSE). Copyright (c) 2026 Craig Waterman.
