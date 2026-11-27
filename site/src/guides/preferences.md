---
title: Preferences
description: "Every tab of Drag Timer Preferences: General, Presets, Routines, Menu bar, Appearance, Feel and Updates."
---

# Preferences

Use the sliders button at the bottom-right of the panel to open **Drag Timer Preferences**, or choose **Settings…**
from the clock's right-click menu. Preferences is split into General, Presets, Routines, Menu bar, Appearance, Feel
and Updates.

## General

General sets the defaults for timers created after the change. Timers that are already running keep what they have.

<figure class="shot">
  <img class="window" src="/drag-timer/images/settings-general.webp" width="1440" height="1256" alt="Preferences, General tab: defaults for new timers, the macOS notification permission and timer behavior" loading="lazy" decoding="async" />
</figure>

| Setting | What it sets |
| --- | --- |
| **Ask for a label after dragging** | Whether releasing a drag offers to name the timer. On by default. |
| **Default name** | What a timer is called when it isn't given a name. |
| **Sound** and **Volume** | The alert sound and how loud it is. |
| **Loop sound until stopped** | Whether the sound repeats until the timer is answered or silenced. |
| **Say the timer's name after the sound** | Whether the name is said aloud when the timer finishes. Off by default. |
| **Show a notification** | Whether a macOS notification is delivered. |
| **Snooze for N min** | The snooze length, which is also the length of **Add N min**. |

Sound can be any of 14 macOS system sounds, or the system beep. A sound plays once when you pick it. System beep
follows your Mac's alert volume. Every other sound, and the spoken name, uses Drag Timer's volume setting.

**macOS notification permission** shows the current answer. If permission has not been requested, use
**Allow Notifications**. If notifications are off or need adjustment, **Open Settings** jumps to the macOS
Notifications pane.

Under **Timer behavior**:

- **Fire timers missed during sleep** chooses whether a timer that ended while the Mac slept fires after wake.
- **Launch at login** starts Drag Timer when you log in.

## Presets

The Quick start buttons: add, edit, duplicate, delete and reorder up to twelve.
[Presets and routines](/drag-timer/docs/presets-and-routines/#presets) covers them.

## Routines

Named sets of timers that start together.
[Presets and routines](/drag-timer/docs/presets-and-routines/#routines) covers them.

## Menu bar

Menu bar chooses what the clock shows while timers run.

<figure class="shot">
  <img class="window" src="/drag-timer/images/settings-menubar.webp" width="1440" height="1256" alt="Preferences, Menu bar tab: Menu bar priority set to Deadline, with Count, Pinned and Ring beside it, and Show zero in count mode" loading="lazy" decoding="async" />
</figure>

| Mode | The clock shows |
| --- | --- |
| **Deadline** | The countdown of the timer that ends soonest, in that timer's color and symbol. This is how it starts. |
| **Count** | How many timers are running. **Show zero in count mode** decides whether a zero is shown when none are. |
| **Pinned** | The timer chosen with **Pin to menu bar** in its **…** menu. |
| **Ring** | A ring that fills, with no digits. It uses the pinned timer when there is one, otherwise the nearest deadline. |

In every mode, a finished timer that has not been answered comes first: the icon turns solid red.
[When a timer ends](/drag-timer/docs/timers/#when-a-timer-ends) has the details.

## Appearance

Appearance controls how countdowns are drawn.

<figure class="shot">
  <img class="window" src="/drag-timer/images/settings-appearance.webp" width="1440" height="1256" alt="Preferences, Appearance tab: Countdown size, High contrast and Urgent treatment, and a note on macOS accessibility settings" loading="lazy" decoding="async" />
</figure>

| Setting | What it sets |
| --- | --- |
| **Countdown size** | The scale of the countdown. |
| **High contrast** | Stronger contrast, or follow the system setting. |
| **Urgent treatment** | How long before its end a timer turns urgent. One minute to begin with. It can start earlier or be turned off. |

An urgent timer turns red and shows an exclamation mark, with a stronger weight. Color is never the only cue.

Drag Timer also follows the macOS accessibility settings Increase Contrast, Differentiate Without Color, Reduce
Transparency and Reduce Motion.

## Feel

Feel controls the drag.

<figure class="shot">
  <img class="window" src="/drag-timer/images/settings-feel.webp" width="1440" height="1256" alt="Preferences, Feel tab: the Preset menu set to Snappy, Maximum drag duration 4 hr, Inertia and Spring sliders, and tactile feedback switches" loading="lazy" decoding="async" />
</figure>

| Setting | What it sets |
| --- | --- |
| **Preset** | **Precise**, **Snappy** or **Throwable**. Snappy is how it starts. |
| **Maximum drag duration** | The longest timer a drag can make, from 4 to 24 hours. |
| **Inertia** | How far a moving release carries on. With inertia off, release starts exactly the duration shown. |
| **Spring** | The shape of a thrown release. It has no effect while inertia is off. |
| **Snap to useful intervals** | Whether the drag catches at snap points. |
| **Snap range** | How close to a snap point the drag has to be to catch. |
| **Use trackpad haptics** | Whether the steps of the ruler can be felt. |
| **Double tick when a snap engages** | A stronger tick at a snap point. |

Precise and Snappy carry no momentum, so both start exactly the length shown at release. Throwable adds momentum
while the pointer is moving, then settles back to the stable preview when you pause.

The ruler itself is fixed. Every step costs the same distance, so familiar durations stay at the same physical
distance whatever is chosen here. Choosing a preset sets the release behavior and the snap range.
**Restore Snappy drag defaults** puts every control of the pane back to how a new install has it.

## Updates

<figure class="shot">
  <img class="window" src="/drag-timer/images/settings-updates.webp" width="1440" height="1256" alt="Preferences, Updates tab: Automatically check for updates, a Check now button, and a note that Drag Timer only opens GitHub Releases" loading="lazy" decoding="async" />
</figure>

- **Automatically check for updates** turns the once-daily check on or off.
- **Check now** runs a check by hand.

When a newer release exists, Drag Timer offers to open its page on GitHub Releases. It never downloads or installs an
update itself. The check requests only public release metadata from GitHub and never uploads timer data.
[Updating](/drag-timer/download/#updating) on the download page has the steps.
