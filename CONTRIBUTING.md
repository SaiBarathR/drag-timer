# Contributing to Drag Timer

Thank you for your interest in contributing! This guide will get you from zero to a running development build as quickly as possible.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| macOS | 14 (Sonoma) or later | Required by the app itself |
| Xcode | Latest stable | **Full Xcode is required** – Command Line Tools alone will not work |
| Swift | Bundled with Xcode | No separate install needed |

> **Why full Xcode?**  
> Drag Timer is a native AppKit/SwiftUI app. The macOS SDK bundled with the Command Line Tools does not include the full Swift standard-library slices needed to build it. If you try to build with CLT only you will see a `failed to build module 'Swift'; this SDK is not supported by the compiler` error.

### Install Xcode

1. Open the **Mac App Store**, search for **Xcode**, and install it (≈ 15 GB).
2. Launch Xcode once to let it finish component installation.
3. Point `xcode-select` at the full toolchain:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

---

## Quick start

```sh
git clone https://github.com/<your-fork>/drag-timer
cd drag-timer
make run       # build (debug) and launch immediately
```

The `Makefile` at the root of the repository provides these targets:

| Command | What it does |
|---|---|
| `make run` | Debug build + launch the app |
| `make build` | Universal release bundle → `dist/Drag Timer.app` |
| `make test` | Full XCTest suite + `--self-test` |
| `make clean` | Remove `.build/` and `dist/` |

> If you prefer not to use Make, the underlying commands are in the README under **Build from source**.

---

## Project layout

```
drag-timer/
├── Sources/DragTimer/     # All application source (AppKit + SwiftUI)
│   ├── Core/              # TimerEngine, models, persistence
│   ├── UI/                # Popovers, preferences, expiry cards
│   └── AppDelegate.swift  # App entry point
├── Tests/                 # XCTest suite
├── Scripts/               # build-app.sh, validate-release.sh, …
├── Packaging/             # Info.plist, icons, entitlements
├── docs/                  # Release notes, checklists
├── plans/                 # Design documents
└── Makefile               # Developer shortcuts (see above)
```

---

## Workflow

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally.
3. Create a **feature branch**: `git checkout -b fix/my-fix` or `feat/my-feature`.
4. Make your changes and run `make test` to verify nothing is broken.
5. Commit with a clear message (see style below).
6. Push your branch and open a **Pull Request** against `main`.

### Commit message style

```
<type>: <short summary in present tense>

<optional body explaining why, not what>
```

Types: `fix`, `feat`, `docs`, `refactor`, `test`, `chore`.

Example:

```
fix: add missing Combine import in TimerPopoverController

Timer.publish returns a Combine publisher. The file was relying on
implicit transitive imports which produced build warnings on Swift 6.
```

---

## Running tests

```sh
make test
# or manually:
swift build
swift test
swift run DragTimer --self-test
```

`swift test` requires the XCTest support included with **full Xcode**. If you see errors about missing XCTest, ensure `xcode-select -p` does **not** point at Command Line Tools.

---

## Known issues & good first contributions

| Area | Description |
|---|---|
| **Intel runtime** | The bundle ships an `x86_64` slice but no Intel Mac was available for testing. Reports (and fixes) from Intel users are very welcome. |
| **Notarization** | Releases are ad-hoc signed. Adding Developer ID signing + Notarization to the GitHub Actions release workflow would remove the Gatekeeper friction for new users. |
| **Localization** | The app is English-only. Adding `.strings` files for other languages would broaden its reach. |
| **Image optimization** | Repository images could be compressed without quality loss (see open ImgBot issue). |
| **Test coverage** | Additional XCTest cases for UI state, drag edge-cases, and settings migration are always welcome. |

---

## Code style

- Follow the existing Swift conventions in each file (spacing, naming, access control).
- Prefer explicit `import` statements over relying on transitive imports.
- Keep UI code in `Sources/DragTimer/UI/` and engine logic in `Sources/DragTimer/Core/`.

---

## License

By contributing you agree that your changes will be released under the [MIT License](LICENSE).

