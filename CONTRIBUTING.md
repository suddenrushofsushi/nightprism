# Contributing

## Development setup

Nightprism is a macOS 14 or newer menu bar app. Development uses Xcode 27.1 with Swift 6.4 in Swift 6 mode, plus XcodeGen 2.46.0.

Install Xcode and XcodeGen, then generate the project:

```sh
xcodegen generate
```

`project.yml` is authoritative. The generated `Nightprism.xcodeproj` is ignored and should not be committed.

The Metal toolchain is required to build. If it is not installed, add it with:

```sh
xcodebuild -downloadComponent metalToolchain
```

## Build and check

Run the test action with signing disabled:

```sh
xcodebuild -project Nightprism.xcodeproj -scheme Nightprism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Check Swift formatting with:

```sh
swift format lint --strict --recursive Sources Tests
```

## Manual smoke checks

Before reporting a change that affects app behavior, run the app and check the relevant behavior. The following areas need real interactive checks:

- Add an overlay from the menu bar.
- Close and reopen the persistent controls window from the menu bar; keep it open while interacting with the target app.
- Select a Safari/Zoom target after granting window access; verify click-through by default.
- Compare dimming and warmth on a white background, dark text, and already-dark regions.
- Enter editing mode, crop the rectangle, then confirm its crop scales as the target resizes.
- Lock it and confirm neither manual movement nor resizing is possible.
- Move another app over the target; keep exposed background content dimmed without tinting the covering app.
- Check minimize, restore, close, pause-all, per-overlay disable, and mixed-scale monitor movement.
- Quit/relaunch: free-standing state persists; foreign-window attachments must be selected again.

## Changes and issues

The current local MVP is tracked in issues #3 and #4. Content detection and launch at login are later
work. Open a GitHub issue to report a bug or propose a feature; keep experimental effects separate
from the window-following and clipping logic.

Keep pull requests focused. Include what changed, how you checked it, and any manual checks that remain pending. Add screenshots when they help explain a visual change.
