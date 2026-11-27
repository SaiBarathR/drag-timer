---
title: Timers
description: Create timers by dragging or typing, change them while they run, answer them when they end, and undo a stop.
---

# Timers

Everything about a single timer: starting one, changing it while it runs, and answering it when it ends.

## Drag one out

Press the menu-bar clock and drag away from it. The floating label moves through a fixed ladder of lengths and shows
the exact time the timer will ring.

| From | To | The label moves |
| --- | --- | --- |
| 1 minute | 15 minutes | every minute |
| 15 minutes | 1 hour | every 5 minutes |
| 1 hour | 4 hours | every 15 minutes |
| 4 hours | the maximum | every 30 minutes |

The longest drag is 4 hours to begin with. [Preferences → Feel](/drag-timer/docs/preferences/#feel) raises it as far
as 24 hours.

Every step costs the same distance, and the ruler never changes: 5 minutes, 15 minutes and 1 hour are always at the
same spot, whatever the maximum or the feel. Raising the maximum only adds length at the far end.

### Snap points and detents

Near common lengths, such as 1, 5, 15 or 30 minutes, the line catches and turns mint. Releasing there starts exactly
that length. On a trackpad each step of the ruler is a tick you can feel, with a stronger one at a snap point.

### Letting go

Release to start the timer. What you get depends on the feel chosen in Preferences:

- **Precise** and **Snappy** start exactly the length shown at release.
- **Throwable** adds momentum while the pointer is moving, then settles back to the stable preview when you pause.

The drag works across built-in and external displays, including mixed Retina and non-Retina setups.

### Backing out

Bring the pointer back onto the icon, where the label reads **Cancel**, and let go. Or press <kbd>Esc</kbd> while
still holding. Neither starts a timer.

## Name it

After a drag, a prompt offers to name the timer. The timer is already running.

- <kbd>Return</kbd> saves the name.
- <kbd>Shift</kbd>-<kbd>Return</kbd> adds a line. The field wraps and takes several lines.
- <kbd>Esc</kbd> keeps the timer under its default name.
- **Discard Timer** removes the timer.

The prompt can be turned off with **Ask for a label after dragging** in
[Preferences → General](/drag-timer/docs/preferences/#general).

## Type a length or a time of day

Click **Other length or time…** under Quick start, type, and press <kbd>Return</kbd>. The button beside the field
names what it read, so you can see it before you start it.

<figure class="shot">
  <img style="width:346px" src="/drag-timer/images/popover-typed.webp" width="692" height="906" alt="The panel with @3:30pm typed into the field and a button beside it reading Ring at 3:30 PM" loading="lazy" decoding="async" />
</figure>

| You type | You get |
| --- | --- |
| `7` | 7 minutes. A bare number is minutes. |
| `25m` | 25 minutes |
| `90s` | 90 seconds |
| `1m 30s` | 1 minute 30 seconds |
| `1h 30m` | 1 hour 30 minutes |
| `1:30` | 1 hour 30 minutes. A colon separates hours and minutes. |
| `@3:30pm` | a timer that rings at 3:30 PM |
| `at 15:30` | a timer that rings at 15:30 |
| `until 4` | a timer that rings the next time the clock reads 4 |

A time of day follows `@`, `at` or `until`. A time from 1 to 12 with no am or pm means the next time the clock reads
it. When the time is tomorrow, the button says so.

A typed timer can be as short as one second. The drag ruler still moves in whole minutes.

## While a timer runs

Each timer has a row in the panel, counting down.

| Control | What it does |
| --- | --- |
| The checkmark | Marks the timer done early. It is recorded in history as completed and never rings. |
| Pause / play | Pauses the timer, or resumes it. |
| **…** | Everything else, below. |

In the **…** menu:

- **Add 1 min**, **Add N min** (the timer's snooze length) and **Subtract 1 min** change how long the timer has left.
  They leave its planned length alone, so **Reset timer** still returns to what was set.
- **Edit timer** changes its label, color and symbol, sound, loop behavior, notification and snooze time. To set an
  exact time, type it into **Time left**: the timer has that long from now, and that becomes its planned length. A
  paused timer stays paused.
- **Pin to menu bar** makes this the timer the menu bar shows in Pinned mode.
- **Reset timer** starts the timer over, **Mark done** finishes it early, and **Cancel timer** removes it.

## When a timer ends

A finished timer plays its sound, shows a macOS notification if those are allowed, and gets a card at the top of the
list that says how long ago it finished.

<figure class="shot">
  <img style="width:346px" src="/drag-timer/images/popover-finished.webp" width="692" height="1058" alt="A red card reading Pasta finished, Just now, with Snooze 5 min, Restart and Mark done buttons and a speaker button" loading="lazy" decoding="async" />
</figure>

- **Snooze** runs it again for its snooze length.
- **Restart** runs it for its whole length again.
- **Mark done** finishes it. <kbd>Return</kbd> does the same.
- The speaker button silences the audio without answering the card.

The notification carries the same three choices.

Until a finished timer is answered, the menu-bar icon is solid red and counts up from the moment it ended (`+2:15`),
ahead of any running countdown. In Ring mode it is a full red ring. In Count mode the red icon sits beside the number,
or alone when no timer is running and the zero is hidden.

Timers that end together are answered one at a time. The card shows one, marked 1 of 2, and answering it leaves the
others waiting.

## Stop all and Undo

**Stop all** at the bottom of the panel cancels every active timer and stops ringing audio. Cards for timers that
have already finished still need their own answer.

For ten seconds after **Stop all**, **Cancel timer** or **Mark done** on a running timer, the panel offers **Undo**.

<figure class="shot">
  <img style="width:346px" src="/drag-timer/images/popover-undo.webp" width="692" height="850" alt="The panel after Stop all: a row reading Stopped 4 timers with an Undo button" loading="lazy" decoding="async" />
</figure>

<kbd>⌘</kbd><kbd>Z</kbd> does the same, except while a length is being typed or Timer details is open, where it
undoes the text. Undo puts the timers back with the end times they had, paused ones still paused, and takes them out
of history. A timer whose end has passed in the meantime finishes and rings at once.

## History

The history button in the panel's footer, or **Timer History** on the clock's right-click menu, opens a list of
completed and cancelled timers.

<figure class="shot">
  <img class="window" style="width:622px" src="/drag-timer/images/history.webp" width="1244" height="1100" alt="Timer History: 5 completed, 4 cancelled, 1 snoozed, 11 min average plan, a filter for All, Completed, Cancelled and Snoozed, and a list of timers each with an Again button" loading="lazy" decoding="async" />
</figure>

- The top row counts completed, cancelled and snoozed timers and shows the average planned length.
- **Filter** narrows the list to completed, cancelled or snoozed timers.
- **Again** starts a timer like that one.
- **Clear history…** empties the list.

History is kept on this Mac and nowhere else. It holds up to 500 entries from the last 90 days.
