# Contributing to Drag Timer

## Prerequisites

- macOS 14 or later.
- Full Xcode 15 or later. Command Line Tools alone cannot build the app or run its tests.

Install Xcode, open it once so it finishes installing components, then select it:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

To leave `xcode-select` unchanged, prefix each command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` instead.

## Quick start

```sh
git clone https://github.com/SaiBarathR/drag-timer.git
cd drag-timer
swift build
swift run
```

`swift run` starts the menu-bar app from the terminal; it has no Dock icon, so press Control-C to quit. To package a universal app bundle instead:

```sh
./Scripts/build-app.sh
open "dist/Drag Timer.app"
```

## Project layout

```
Sources/DragTimer/
├── App/            Entry point, app delegate, settings, presets, routines
├── Audio/          Alert sounds
├── Engine/         Timer engine, deadline heap, persistence
├── History/        Timer history store and window
├── Notifications/  Notification delivery and permission handling
├── Physics/        Drag distance and velocity to duration mapping
├── Render/         Drag overlay window and display-link driver
├── StatusItem/     Menu-bar item, drag gesture, countdown presentation
├── UI/             Popover, label prompt, settings window, appearance
└── Updates/        Update checker
Tests/DragTimerTests/   XCTest suite
Scripts/                build-app.sh, validate-release.sh and its test
Packaging/              Info.plist and app icon sources
docs/                   Release notes, release checklists, README images
plans/                  Product and release plans
drag-timer-macos-native.md   Original architecture plan
```

## Workflow

1. Fork the repository and create a branch from `main`, for example `fix/13-multi-display-drag-overlay`.
2. Make the change and run the checks below.
3. Open a pull request against `main` and reference the issue it resolves, for example `Fixes #13`.

Write commit subjects as a short imperative sentence, as the existing history does: `Fix menu-bar timer dragging on macOS 27`. Use the body to explain why the change is needed.

## Running tests

```sh
swift build
swift test
```

`swift test` needs the XCTest support that ships with full Xcode; if it reports XCTest as missing, `xcode-select -p` is pointing at Command Line Tools. CI also runs `./Scripts/test-validate-release.sh` and `./Scripts/build-app.sh`, so run those too when you touch release scripts or packaging.

## Good first contributions

- **Intel runtime testing.** Releases ship an `x86_64` slice that has not been tested on a physical Intel Mac. Reports and fixes from Intel users are welcome.
- **Localization.** The app is English-only and has no localized string resources yet.
- **Test coverage.** New cases belong in `Tests/DragTimerTests/`.

## License

By contributing you agree that your changes are released under the [MIT License](LICENSE).
