# Drag-Physics Timer for macOS — Native Architecture Plan

A menu bar timer app whose entire competitive advantage is **how it feels**: a press-and-drag from the menu bar icon where drag *distance + velocity* maps to a duration through real physics, rendered at full ProMotion refresh with spring settling and haptic snapping. macOS-only, single native codebase.

---

## 0. The thesis

Gestimer proved the gesture is great. DragTime proved you can pile on features. Both reportedly **feel laggy**. That gap *is* the product: feature parity is not the goal — **motion quality is**. Every architectural choice below is in service of one sentence: *the drag must be perfectly smooth, the physics must feel real, and the snap must be tactile.*

Concretely, that means three differentiators the incumbents underuse:
1. **Frame-rate-locked rendering at 120 Hz** (ProMotion), driven by the display's own vsync — not a fixed-interval timer.
2. **Genuine inertia** — a fast flick "throws" the value further, with a spring that settles instead of snapping hard.
3. **Haptic feedback on snap** — a trackpad tick when the value latches to a nice increment. Almost nobody does this, and it's the single cheapest "premium" cue available.

---

## 1. Why the competitors likely feel laggy (the things to NOT do)

Diagnosing the probable causes tells you exactly what to engineer around. The usual culprits for a janky drag overlay on macOS:

- **Driving animation with a fixed `Timer`/`NSTimer`** (e.g. 60 fps assumed) instead of a `CADisplayLink` synced to the actual display. On a 120 Hz panel this produces visible judder.
- **Re-laying-out views every frame.** Animating via Auto Layout constraint changes or SwiftUI body re-evaluation per frame triggers layout passes. The drag line must be a single `CALayer`/`CAShapeLayer` whose `path`/`transform` is updated directly — no layout.
- **Main-thread string work each frame:** formatting "1h 23m" via `DateComponentsFormatter` 120×/second allocates and churns ARC. Pre-format lazily / throttle the label to ~30 Hz while keeping the line at full rate.
- **Per-frame allocations** (new arrays, new `NSAttributedString`s) causing retain/release stalls. Pre-allocate; mutate in place.
- **The overlay window stealing focus / activating**, causing flicker and a beat of latency. It must be a borderless **non-activating** panel.
- **No velocity model** — value tracks the cursor 1:1 with zero inertia, which reads as "cheap." Real momentum is what makes it feel physical.

If you avoid this list, you've already beaten them on feel before adding a single feature.

---

## 2. Recommended stack (native, lean)

**Swift, with a deliberate split:**

| Concern | Technology | Why |
|---|---|---|
| Menu bar icon + drag capture | **AppKit** (`NSStatusItem` custom button) | Only AppKit gives you mouseDown→drag→up on the status item. This is the proven path. |
| Drag overlay rendering | **Core Animation** (`CAShapeLayer`/custom `CALayer`), optionally **Metal** (`CAMetalLayer`) | GPU-composited, near-zero CPU, sub-pixel crisp. Metal only if you want shader effects (glow/trail). |
| Frame timing | **`CADisplayLink`** (macOS 14+) | Auto-syncs to the panel's real refresh, including ProMotion 120 Hz. |
| Physics | **Custom damped-spring integrator** stepped by display-link `dt` | Full control over inertia + settling; frame-rate independent. |
| Timer list & settings UI | **SwiftUI** | Fast to build chrome that isn't on the hot path. |
| Audio | **AVFoundation** (`AVAudioPlayer`) | Lazy-loaded alert/music. |
| Notifications | **UserNotifications** (`UNUserNotificationCenter`) | Native, OS-delivered even if app is busy. |
| Haptics | **`NSHapticFeedbackManager`** (`.alignment`) | Trackpad tick on snap — the premium cue. |
| Persistence | **Codable JSON file** (or UserDefaults for config) | Lowest overhead; absolute fire dates. |

**Why native over Tauri/Flutter now that it's macOS-only:** native is the lowest-memory option (idle ~20–40 MB vs ~80+), and it's the *only* path that gives you Core Animation / Metal and `CADisplayLink` directly — i.e. the exact tools that produce the feel you're selling. With one OS, the multi-codebase downside of native disappears. This is the right call.

**App type:** agent app — set `LSUIElement = YES` in Info.plist so there's no Dock icon, menu bar only.

---

## 3. The drag interaction, natively

1. **`NSStatusItem` with a custom button** that handles `mouseDown`. On mouse-down, start the gesture; once a drag begins, the button captures subsequent `mouseDragged` events even outside its bounds (standard AppKit drag tracking), so you get a continuous stream of cursor positions in screen coordinates.
2. **Spawn a transparent overlay window** (`NSPanel`, `styleMask = .borderless | .nonactivatingPanel`, `isOpaque = false`, `backgroundColor = .clear`, `level = .statusBar`, `ignoresMouseEvents = false`). Size it to cover the screen(s) the drag spans. This window hosts the Core Animation layer that draws the line/arc from the icon down to the cursor plus the live duration label.
3. **On each `mouseDragged`**, push the new cursor position + timestamp into the physics layer (don't render here — see §5). The display link does the rendering.
4. **On `mouseUp`**, read the current cursor velocity, run the inertia projection + spring settle + snap, commit the timer, fire a haptic if it snapped, and tear the overlay down. Killing the overlay (and the display link) immediately means **zero render cost when idle**.

Multi-display: track which screen the cursor is on; either span one window across the union of screen frames, or one overlay per screen. AppKit handles per-screen backing scale (Retina/DPI) automatically.

Optional, later: modifier-key variants (e.g. a key + drag for a different timer style) — but resist DragTime's feature sprawl until the core feel is undeniable.

---

## 4. Physics model (carried from the design, tuned for native)

### 4.1 Distance → duration (exponential, for minute-to-hour control)

```
n = clamp(distance / D_ref, 0, 1)
T(n) = T_min * (T_max / T_min) ^ (n ^ γ)        // seconds
```
- `D_ref` = reference drag length (e.g. 50% of screen height) — the "length" knob.
- `γ` > 1 packs fine resolution into the start of the drag — the "feel" knob.
- Exponential mapping is what makes a short drag read as minutes and a long drag as hours, with even relative precision throughout.

### 4.2 Velocity → inertia (the "throw")

Sample `(position, time)` every drag event; smooth velocity with an EMA to kill jitter. On release:
```
d_eff   = distance + v_release * k_inertia
T_final = T(clamp(d_eff / D_ref, 0, 1))
```
`k_inertia` is the "throw strength" knob; an aggressive, still-accelerating flick can scale it up so a flick reaches hours fast. This momentum is the difference between "physical" and "cheap."

### 4.3 Spring settle + haptic snap

- **Settle:** animate the displayed value from current → `T_final` with a damped spring integrated per display-link frame (`stiffness`, `damping`). Slightly under-damped reads as alive; critically damped reads as crisp. Expose as a preset.
- **Snap (optional, on by default):** snap points at 1/5/15/30 min, 1 h, … . If `T_final` is within ε, attract to it **and** fire `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` for a trackpad tick. Optionally tick during the drag as the value crosses each snap point — that continuous tactile feedback is a standout premium detail.

### 4.4 Tunable "feel" parameters

`T_min`, `T_max`, `D_ref`, `γ`, `k_inertia`, spring `stiffness`/`damping`, snap on/off + granularity, haptics on/off. Ship presets ("Precise", "Snappy", "Throwable") plus manual control. Respect **Reduce Motion** (System Settings accessibility): when on, shorten/disable the spring and inertia.

---

## 5. The render pipeline (where "buttery" is won)

A strict separation that guarantees smoothness:

```
mouseDragged  ──►  [Physics state]   (just store position + time; no drawing)
                        │
   CADisplayLink ──► step physics by real dt ──► update CALayer.path / .transform
   (vsync, 60/120Hz)                              update label ~30Hz (throttled)
```

Rules:
- **One display link** owns all motion; mouse events only mutate state. This decouples input rate from frame rate and is the core anti-jank move.
- **Step physics by the link's actual `dt`** so behavior is identical at 60 and 120 Hz and never speeds up/slows down on a dropped frame.
- **Mutate layer properties, never layout.** The drag line is a `CAShapeLayer`; update its `path` (or use a `transform` on a static shape). Disable implicit animations (`CATransaction` with actions disabled) so each frame is your value, not Core Animation's own interpolation fighting you.
- **Throttle the text label** to ~30 Hz and pre-format; the eye can't read faster and `DateComponentsFormatter` is expensive.
- **No allocations in the frame callback.** Reuse buffers, pre-build the attributed string template.
- **Tear everything down on mouse-up** — invalidate the display link, close the overlay. Idle app = no GPU, no CPU.

If you want a visible "premium" flourish, a `CAMetalLayer` with a simple shader (soft glow + a fading motion trail behind the line) is cheap on the GPU and instantly differentiates from the competitors' flat lines — but ship the Core Animation version first.

---

## 6. Timer engine (correct, and near-free at idle)

- **Store absolute fire `Date`s**, never countdowns. Remaining time is derived. This makes the app immune to drift and to sleep (a `Date` is wall-clock, so it stays correct across system sleep automatically).
- **One scheduler, a min-heap of deadlines.** A single `DispatchSourceTimer` armed for the *earliest* deadline; on fire, pop and re-arm. No per-timer timers, no polling. O(log n) inserts.
- **Belt-and-suspenders delivery:** also schedule a `UNTimeIntervalNotificationTrigger` (or calendar trigger) per timer so the OS delivers the alert even if the app is momentarily busy. The in-app timer drives live UI + sound; the OS notification guarantees the user is told.
- **Sleep/wake:** on wake, fire anything past-due (configurable: fire-on-wake vs. mark-missed). Subscribe to `NSWorkspace` sleep/wake notifications to re-arm the source.
- **Persistence:** Codable JSON of `{label, fireDate, sound, volume, loop, notify, snooze}`. Rebuild the heap on launch; surviving timers resume from their absolute dates. Crash-safe by design.
- **Menu bar:** static icon at idle (optionally a tiny count badge). When the popover/list is open, render the countdown at ~1 Hz only.

---

## 7. Audio, notifications, settings

- **Audio:** `AVAudioPlayer`, loaded at fire time and released after playback — never hold decoded audio for pending timers. Support per-timer alert vs. music file, volume, loop. Ship a small set of tasteful built-in sounds (quality over DragTime's quantity).
- **Notifications:** request `UNUserNotificationCenter` authorization on first run. Offer native banner and an optional full-screen alert overlay (reuse the overlay-window infrastructure from the drag). Sound played by the audio engine so it's controllable.
- **Per-timer settings:** label, sound, volume, loop, notification style, snooze.
- **Global settings:** the §4.4 feel parameters + presets, default sound, launch-at-login (`SMAppService`), theme.

---

## 8. Performance budget

| State | CPU | Memory |
|---|---|---|
| Idle, timers pending | ~0% | ~20–40 MB |
| List/popover open | <1% (1 Hz countdown) | same |
| Active drag | one core light + brief GPU; **steady 120 fps** | same |

Hold the line: no polling, render loop exists only during the drag, single scheduler, absolute-date timers, zero per-frame allocations, audio freed after use.

---

## 9. Project structure

```
/App            AppDelegate, LSUIElement setup, lifecycle
/StatusItem     NSStatusItem custom button, drag capture, overlay window mgmt
/Render         CADisplayLink driver, CALayer/Metal drag surface, label rendering
/Physics        distance→duration curve, velocity/inertia, spring, snapping (pure, testable)
/Engine         min-heap scheduler, absolute-date timers, persistence, sleep/wake
/Audio          AVFoundation playback
/Notifications  UNUserNotificationCenter, full-screen alert overlay
/UI             SwiftUI timer list + settings + feel presets
/Resources      sounds, icons
```

`/Physics` and `/Engine` are pure and unit-tested; everything visual is thin glue over them.

---

## 10. Roadmap

1. **Spike the feel first.** Build *only*: status-item drag → overlay → `CADisplayLink` → spring + inertia + haptic snap. No timers yet. If this doesn't feel better than Gestimer/DragTime in your hand, nothing else matters — iterate here until it does.
2. **Timer engine** (min-heap, absolute dates, notifications, sleep/wake) + persistence.
3. **Multiple timers + menu bar list + per-timer settings.**
4. **Audio + notification styles (incl. full-screen alert).**
5. **Feel presets + Reduce Motion + multi-display polish + launch-at-login.**
6. **Optional Metal flourish** (glow/trail) once the core is rock-solid.

---

## 11. Premium levers that out-class the incumbents

- **True ProMotion 120 Hz** via `CADisplayLink` (most fixed-timer apps don't).
- **Real inertia + spring settle** — the "throw" feel.
- **Haptic snap ticks** on the trackpad — rare, and disproportionately "expensive-feeling."
- **Frame-rate-independent physics** so it's identical on every Mac.
- **Sub-frame-crisp rendering** with disabled implicit animations.
- **Idle at ~0% CPU / ~30 MB** — the anti-"buggy/laggy" reputation, and a real selling point you can put on the page.
- **Respecting Reduce Motion** — signals craft and accessibility care.

---

## 12. Open decisions for you

- **Core Animation vs. Metal for the drag surface:** start with Core Animation (enough to win); add a Metal layer only if you want shader effects as a marketing screenshot.
- **SwiftUI vs. AppKit balance:** SwiftUI for list/settings is fine; keep the hot drag path pure AppKit + Core Animation. Decide if you're comfortable bridging the two (you are — `NSHostingView` makes it trivial).
- **Snap-during-drag haptics:** continuous ticks (more delightful, slightly busier) vs. only on release. Try both in the spike.
- **macOS minimum version:** targeting 14+ gives you `CADisplayLink`; going lower means `CVDisplayLink` (more boilerplate). DragTime targets 14.6+, which is a reasonable floor.
- **Scope discipline:** decide now to ship the *feel* first and add reminders/calendar/Shortcuts only after — or you'll rebuild DragTime and inherit its complexity.
