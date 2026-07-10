# Drag Timer

Drag Timer is a native macOS menu-bar timer built around a single gesture: pull time out of the menu-bar icon, release it, and the timer starts. Distance chooses the duration, release speed adds momentum, and useful intervals snap into place with trackpad feedback.

It is a Swift/AppKit app for macOS 14 and later. It has no Dock icon and keeps timers in `~/Library/Application Support/DragTimer/timers.json`.

## Screenshots

<p align="center">
  <img src="docs/images/preferences-defaults.jpg" alt="Drag Timer Preferences showing defaults for new timers" width="360" />
  <img src="docs/images/preferences-feedback.jpg" alt="Drag Timer Preferences showing drag and tactile feedback controls" width="360" />
</p>

## What it does

- Create a timer by dragging from the menu-bar clock icon.
- View, edit, snooze, or cancel timers from the menu-bar popover.
- Use Glass or the system beep, with per-timer volume, notification, snooze, and loop settings.
- Set defaults for every new timer in Preferences.
- Snap to useful durations and feel a haptic tick when crossing a snap point.
- Keep timers correct across sleep, wake, and relaunch by storing absolute fire dates.
- Optionally launch at login and choose whether missed timers fire after wake.

## Install a release

Releases include `Drag-Timer-<version>-macos-unsigned.zip` and `SHA256SUMS.txt`.

1. Download and unzip the archive from the [Releases](https://github.com/SaiBarathR/drag-timer/releases) page.
2. Move `Drag Timer.app` to Applications.
3. Because releases are intentionally unsigned and not notarized, macOS will show a Gatekeeper warning on first launch. Control-click the app, choose **Open**, then confirm; alternatively use **Open Anyway** in System Settings → Privacy & Security.
4. Drag from the menu-bar timer icon to create your first timer.

Verify the published SHA-256 checksum before opening a downloaded build when you want to confirm its integrity.

## Use

### Create and manage timers

- Click the menu-bar icon to open the timer list. Clicking anywhere outside the popover closes it.
- Press and drag away from the icon. The floating label shows the current duration in real time.
- Release to start the timer. Releasing near common values—such as 1, 5, 15, or 30 minutes—snaps to that duration.
- Open the `…` menu beside a timer to edit its label, sound, loop behavior, notification, and snooze time.

### Preferences

Use the sliders button at the bottom-right of the timer popover to open **Drag Timer Preferences**.

The top section controls defaults for timers created after the change:

- Timer name, alert sound, and volume
- Loop-until-stopped behavior
- Notification delivery and snooze length

The rest of the window controls drag feel, snap range, trackpad haptics, wake behavior, and launch at login. System beep follows your Mac’s alert volume; Glass uses Drag Timer’s volume setting.

## Build from source

```sh
swift build
swift run
```

Build an app bundle:

```sh
./Scripts/build-app.sh
open "dist/Drag Timer.app"
```

The script deliberately produces an **unsigned** app bundle. It is suitable for local use and the public release workflow, but it is not notarized for frictionless distribution.

## Verify

The deterministic checks cover duration mapping, inertial release, spring settlement, persistence, timer defaults, and the looping-alert priority path.

```sh
swift build
swift run DragTimer --self-test
```

## Release automation

GitHub Actions is configured for macOS 14:

- [CI](.github/workflows/ci.yml) runs on pushes to `main` and pull requests. It builds the app, runs self-checks, packages the unsigned bundle, and confirms it is not signed.
- [Release](.github/workflows/release.yml) runs when a `v*` tag is pushed. It builds the tagged source, creates an unsigned ZIP and SHA-256 checksum, then publishes them to the matching GitHub release.

To publish a new version after updating `Packaging/Info.plist`:

```sh
git tag -a v1.0.0 -m "Drag Timer 1.0.0"
git push origin v1.0.0
```

## Architecture

- AppKit owns status-item input, overlay windows, and app lifecycle.
- SwiftUI provides the timer list, editor, and Preferences interface.
- Core Animation renders the drag line and duration overlay at display cadence.
- `TimerEngine` schedules only the nearest deadline and persists timers as Codable JSON.
- `AVAudioPlayer` handles Glass looping; system-beep looping is repeated until stopped.

## Privacy

Drag Timer does not require an account or send timer data to a service. Notifications are requested from macOS only when the packaged app runs; timer data remains on the local Mac.
