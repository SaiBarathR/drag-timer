# Drag Timer: broad public release readiness plan

Date: 2026-07-14
Status: implementation complete; clean-machine release-candidate evidence pending
Target release: `v1.3.1` (or the next available patch version)
Target: native macOS 14+ menu-bar app distributed through GitHub Releases

## Goal

Prepare Drag Timer for a broad public announcement, excluding Developer ID signing and notarization. The resulting release must:

- run natively on both Apple Silicon and Intel Macs supported by macOS 14;
- be impossible to publish unless tests, version checks, packaging checks, and checksum generation pass;
- have clean-machine evidence for the user journeys automated tests cannot prove;
- include a real app icon, an explicit source license, accurate installation/support documentation, and useful release notes.

Do not replace or retag `v1.3.0`. It is already public and should remain an immutable historical artifact. Publish the corrected package as a new patch release.

## Current baseline

- `main` and `origin/main` are aligned at tagged version `v1.3.0`.
- The current XCTest suite has 58 passing tests and the deterministic self-check passes.
- The published `v1.3.0` ZIP checksum and ad-hoc signature verify successfully.
- The published executable is a thin `arm64` binary.
- The release workflow builds and publishes without running the test suite or checking the tag against `CFBundleShortVersionString`.
- The bundle has no application icon.
- The repository has no explicit license.
- The README's release example still uses `v1.0.0`.
- The generated release description is generic and does not explain the actual changes in `v1.3.0`.

## Release policy decisions

Resolve these before implementation is called complete:

1. **Architecture:** ship a universal `arm64 + x86_64` app. If Swift or a future dependency prevents this, explicitly change the supported audience to Apple Silicon and treat that as a conscious product limitation, not an undocumented fallback.
2. **License:** choose one of the following and record the choice in the repository:
   - MIT, recommended if users should be able to inspect, modify, and redistribute the source.
   - An all-rights-reserved source-available notice if the repository is public only for transparency and issue reporting.
3. **Release number:** use `v1.3.1` unless another release has claimed that version before this work lands.

## Phase 1 — universal application packaging

### Implementation

- Update `Scripts/build-app.sh` to produce one universal executable containing `arm64` and `x86_64` slices.
- Prefer SwiftPM's multi-architecture release build when it produces a correct fat executable. If it is unreliable, build each architecture into isolated scratch directories and combine the two executables with `lipo -create`.
- Continue assembling the bundle from a clean directory and applying an ad-hoc signature only after the universal executable and resources are in place.
- Make the script fail unless `lipo -archs` reports exactly `arm64 x86_64`, independent of output order.
- Keep `LSMinimumSystemVersion` aligned with `Package.swift` at macOS 14.0.
- Update CI to assert the executable is universal and the final bundle has a valid ad-hoc signature.

### Verification

```sh
./Scripts/build-app.sh
lipo -archs "dist/Drag Timer.app/Contents/MacOS/DragTimer"
codesign --verify --deep --strict --verbose=2 "dist/Drag Timer.app"
plutil -p "dist/Drag Timer.app/Contents/Info.plist"
```

Acceptance criteria:

- The architecture check contains both `arm64` and `x86_64` and no unexpected slice.
- The app launches natively on an Apple Silicon Mac.
- The Intel slice is built in CI and is launched on real Intel hardware if an Intel test Mac is available. If hardware is unavailable, document that execution remains unverified rather than claiming it was tested.
- The archived ZIP preserves both slices and the signature after download and extraction.

## Phase 2 — self-gating release automation

### Release validation script

Add a small script such as `Scripts/validate-release.sh` that:

- accepts the tag being released;
- requires the tag format `vMAJOR.MINOR.PATCH`;
- reads `CFBundleShortVersionString` from `Packaging/Info.plist`;
- fails when the tag version and plist version differ;
- requires `CFBundleVersion` to be a positive integer;
- requires a release-notes file for that version;
- prints the validated version for later workflow steps.

Test the validator with at least:

- a matching tag and plist;
- a mismatched tag;
- malformed tags;
- missing release notes;
- invalid bundle version values.

The tests may be shell-level checks in CI or XCTest coverage around a shared version parser, but the exact command used by the release workflow must be exercised.

### Release workflow order

Change `.github/workflows/release.yml` so publishing cannot begin until every preceding gate succeeds:

1. Check out the exact tag.
2. Validate the tag, plist version, bundle build number, and release-notes file.
3. Run `swift build`.
4. Run `swift test`.
5. Run `swift run DragTimer --self-test`.
6. Build the universal app bundle.
7. Verify both architecture slices.
8. Verify the ad-hoc signature.
9. Archive the app.
10. Generate `SHA256SUMS.txt` from the final archive.
11. Extract the archive into a clean temporary directory and re-check version, architectures, signature, and checksum.
12. Publish the release only after all checks pass.

Additional safeguards:

- Add workflow concurrency keyed by the tag so duplicate runs cannot race to update the same release.
- Use explicit least-privilege permissions: read access during validation and `contents: write` only where publishing requires it, if job separation is practical.
- Do not rely on the separate branch CI run completing successfully; the tag workflow must independently prove the artifact it publishes.
- Do not silently overwrite an existing published release asset. Fail and require a deliberate operator decision if the tag or asset already exists.

Acceptance criteria:

- A deliberately mismatched test tag fails before packaging.
- A deliberately failing test prevents the release from being created or updated.
- A successful dry run produces the same ZIP and checksum structure as the real publish job.
- The published asset downloaded from GitHub passes the same post-archive verification commands.

## Phase 3 — application icon

### Asset work

- Create an original 1024×1024 master icon that visually connects the menu-bar clock with Drag Timer's pull/drag interaction.
- Check it at small sizes; the silhouette must remain readable at 16, 32, and 64 pixels.
- Generate the complete macOS iconset: 16, 32, 128, 256, and 512 point images at 1× and 2×.
- Compile it into `AppIcon.icns` with `iconutil` and store the source/master asset in a maintainable repository location.

### Bundle integration

- Copy `AppIcon.icns` into `Contents/Resources` in `Scripts/build-app.sh`.
- Add the appropriate icon key to `Packaging/Info.plist`.
- Build from a clean `dist/` directory so an old resource cannot hide a packaging mistake.

Acceptance criteria:

- Finder, the Open confirmation dialog, System Settings, and app information display the intended icon.
- The icon is present in the ZIP downloaded from GitHub.
- Light and dark desktops and small Finder sizes do not make the icon illegible.
- The menu-bar glyph remains a native template image and is not replaced by the full application icon.

## Phase 4 — license and public-facing documentation

### License

- Make the license decision from the policy section.
- Add a root `LICENSE` file with the exact chosen terms and copyright holder/year.
- Add a short License section to the README linking to that file.
- Do not label the project "open source" unless the chosen license actually grants open-source rights.

### README corrections

- Replace the hard-coded `v1.0.0` release commands with a clearly named placeholder such as `vX.Y.Z`, plus a concrete current example only where useful.
- State that release artifacts are universal and support Apple Silicon and Intel Macs on macOS 14+ after universal packaging is verified.
- If universal packaging is abandoned, state "Apple Silicon only" prominently in the introduction, installation section, asset name, and release notes.
- Keep the ad-hoc-signing/Gatekeeper instructions accurate and avoid implying the application is Developer ID signed or notarized.
- Add the application icon to the top of the README if it renders cleanly at documentation size.
- Review screenshots against the current `v1.3.x` UI and replace any image that no longer represents the shipped app.

Acceptance criteria:

- A new contributor can determine supported macOS versions, CPU architectures, signing status, license, install steps, verification steps, and release procedure without inspecting source files.
- Every README command is copied into a shell and checked before release.
- Repository links and images render correctly on GitHub.

## Phase 5 — meaningful release notes

### Existing `v1.3.0`

- Write proper retrospective notes covering named timer routines, the six-feature product work, migration behavior, supported systems, installation, and known signing/Gatekeeper limitations.
- Edit the existing GitHub release description without replacing its tag or binary assets.

### Future releases

- Add a tracked release-notes file such as `docs/releases/v1.3.1.md` for every release.
- Make the release validator fail if the matching notes file is absent.
- Have the workflow use that file as the GitHub release body rather than a generic one-line message.
- Structure notes with: Highlights, Changes, Compatibility, Installation, Verification, Known limitations, and checksum instructions.
- Include migration or data-compatibility notes whenever persisted timer/settings formats change.

Acceptance criteria:

- `v1.3.0` has useful human-written notes even though its artifact remains unchanged.
- The next patch release body comes directly from the reviewed tracked notes file.
- Release notes accurately state architecture support and ad-hoc-signing limitations.

## Phase 6 — clean-machine manual smoke test

Run this against the exact ZIP downloaded from the draft or published release—not against a locally built app. Prefer a new macOS user account or a Mac that has never run Drag Timer. Record macOS version, hardware architecture, artifact checksum, tester, date, and result.

### Installation and first launch

- Verify the published SHA-256 checksum.
- Extract the ZIP and confirm the app is not quarantined or damaged by packaging.
- Move it to Applications.
- Follow the documented Control-click/Open or Open Anyway path.
- Confirm there is no Dock icon and the menu-bar item appears once.
- Confirm the application icon appears in Finder and system surfaces.

### Core timer interaction

- Drag from the menu-bar icon and confirm duration text is legible.
- Cross several snap points and confirm detent feedback.
- Release stationary and with momentum; confirm the selected duration matches the preview rules.
- Create timers using Quick start and a named routine.
- Pause, resume, reset, edit, cancel, pin, and Stop all.

### Expiry, audio, and notifications

- Test Glass and system beep at non-default volume.
- Test one-shot and looping alerts.
- Allow notifications from the packaged app and verify audible delivery.
- Exercise Snooze, Restart, Mark done, and silence actions.
- Expire multiple timers together and confirm looping-audio priority and independent expiry cards.

### Persistence and system lifecycle

- Relaunch with running, paused, and unresolved expired timers.
- Put the Mac to sleep across a deadline, then verify both missed-timer preference modes.
- Reboot or sign out/in with Launch at login enabled and disabled.
- Confirm settings, rich presets, routines, pinned timer choice, history, and unresolved expiries survive as intended.
- Confirm updating from the prior public version preserves existing user data.

### Secondary surfaces

- Check Preferences tabs, History, update checking, GitHub release opening, light/dark appearance, Increase Contrast, Reduce Motion, keyboard navigation, and VoiceOver labels.
- Confirm clicking outside closes the popover and that popover placement remains correct with no timers, several timers, and routines visible.

### Required test environments

- Apple Silicon Mac on macOS 14 or newer: full checklist.
- Intel Mac on macOS 14: at minimum install, launch, drag creation, Quick start, expiry/audio/notification, relaunch persistence, and quit.
- If Intel hardware cannot be obtained, record Intel runtime testing as an explicit open risk even though the binary contains an Intel slice.

Store the completed checklist in a tracked file such as `docs/release-checklists/v1.3.1.md`. Attach screenshots or short screen recordings only where they help prove visual or system-level behavior.

Acceptance criteria:

- No severity-1 or severity-2 issue remains open.
- Every checklist row has Pass, Fail, or Not tested plus a reason; blank rows are not acceptable.
- Any failed behavior is fixed and the entire affected section is rerun against a newly downloaded artifact.

## Phase 7 — release candidate and announcement gate

### Release candidate sequence

1. Complete phases 1–5 on a feature branch.
2. Run local build, tests, self-check, universal packaging, signature verification, and README command verification.
3. Open a PR and require green CI.
4. Merge without tagging.
5. Produce a release-candidate artifact from the exact intended commit.
6. Complete the clean-machine checklist against that artifact.
7. Bump `CFBundleShortVersionString` and `CFBundleVersion` if not already final.
8. Add and review `docs/releases/v1.3.1.md`.
9. Create and push the annotated tag only after the go/no-go gate passes.
10. Download the published assets and repeat checksum, architecture, signature, version, and extraction verification.

### Final go/no-go gate

The broad announcement is **GO** only when all of the following are true:

- [ ] Universal Apple Silicon and Intel artifact verified.
- [ ] Release tag exactly matches bundle version.
- [ ] Tests and self-check run inside the release workflow.
- [ ] Post-archive verification passes inside the release workflow.
- [ ] App icon is present and verified in the downloaded artifact.
- [ ] License choice is explicit in `LICENSE` and README.
- [ ] README accurately documents architectures, macOS requirement, Gatekeeper flow, verification, and release commands.
- [ ] `v1.3.0` retrospective notes are published.
- [ ] Next-release notes are reviewed and tracked.
- [ ] Apple Silicon clean-machine checklist passes.
- [ ] Intel clean-machine checklist passes, or Intel runtime support is explicitly held back.
- [ ] Downloaded GitHub asset matches its checksum and contains the expected version and architectures.
- [ ] No high-severity release issue is open.

## Expected files

Likely additions or changes during implementation:

- `Scripts/build-app.sh`
- `Scripts/validate-release.sh`
- `Packaging/Info.plist`
- `Packaging/Resources/AppIcon.icns`
- the maintainable master/iconset source under `Packaging/` or `docs/`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `README.md`
- `LICENSE`
- `docs/releases/v1.3.0.md`
- `docs/releases/v1.3.1.md`
- `docs/release-checklists/v1.3.1.md`
- validator tests or fixtures

## Out of scope

- Developer ID signing.
- Apple notarization.
- Mac App Store distribution.
- Automatic in-app installation or replacement.
- Telemetry or crash-reporting services.
- Changing timer product behavior unless the clean-machine test finds a release-blocking defect.
