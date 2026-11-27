---
title: Getting started
description: Open Drag Timer for the first time, pull your first timer out of the menu bar, and find your way around the panel.
---

# Getting started

Drag Timer is the small clock in the menu bar. It has no Dock icon and no main window: press the clock, drag away
from it, and let go. This page covers the first launch, the first timer and where everything is.

If you haven't installed it yet, the [download page](/drag-timer/download/) has the steps, including the one-time
Gatekeeper confirmation.

## The guide

The first time Drag Timer is opened it puts up a guide in a window of its own: what the app is for, where each thing
is, and every key and click it answers. An update from a version without the guide shows it once as well.

<figure class="shot">
  <img class="window" src="/drag-timer/images/guide-pull.webp" width="1800" height="1240" alt="The Welcome Guide, page 1 of 7: Pull a timer out of the menu bar, with a drawing of the drag and four numbered tips" loading="lazy" decoding="async" />
</figure>

It has seven pages. Six are about a part of the app, each with a picture of that part: the drag, Quick start, running
timers, finished timers, the menu bar and Preferences. The seventh lists the keys.

- <kbd>Return</kbd> and <kbd>→</kbd> turn its pages, <kbd>←</kbd> turns back, and <kbd>Esc</kbd> shuts it.
- The app goes on working behind it, so a timer can be dragged out with the page that describes the drag still on
  screen.
- On a first launch, shutting the guide opens the panel, which shows where in the menu bar the clock is.

The guide opens by itself only that once. Afterwards it is **Welcome Guide** on the clock's right-click menu and
under **More** at the bottom of the panel.

## Your first timer

1. Press the clock in the menu bar and hold the button down.
2. Drag away from it. A line follows the pointer, and a floating label shows the length and the exact time the timer
   will ring.
3. Let go. The timer starts at that moment.

A prompt then offers to name the timer. <kbd>Return</kbd> saves the name, <kbd>Esc</kbd> keeps the timer under its
default name, and **Discard Timer** removes it. The timer is already running while you type, so a 5-minute drag is 5
minutes however long the name takes.

<figure class="shot">
  <img class="window" style="width:390px" src="/drag-timer/images/name-prompt.webp" width="780" height="528" alt="The Name this timer prompt, reading Running, rings at 1:28 PM, 25:00 left, with Deep work typed in" loading="lazy" decoding="async" />
</figure>

macOS asks whether to allow notifications when you start your first timer. Preferences → General shows the answer
and can take you to the macOS Notifications pane to change it.

[Timers](/drag-timer/docs/timers/) has the rest: how the drag steps through lengths, how to back out, and what to do
when a timer ends.

## The panel

A click on the clock, with no drag, opens the panel. A click anywhere outside it shuts it again.

<figure class="shot">
  <img style="width:346px" src="/drag-timer/images/popover-running.webp" width="692" height="896" alt="The panel with Quick start presets at the top, two routines, three running timers, and a footer with Stop all and three buttons" loading="lazy" decoding="async" />
</figure>

From the top:

| Part | What it is |
| --- | --- |
| **Quick start** | A button for each preset. A click starts a timer of that length at once. |
| **Other length or time…** | A field for any other length, or a time of day. |
| **Routines** | Each starts several timers together. The strip appears once a routine has been made. |
| The timer list | A row for each timer, counting down, and above them a card for one that has finished. |
| The footer | **Stop all**, then the History, Preferences and **More** buttons. |

With no timers, the footer says so and the list reminds you that any length can be pulled from the menu-bar icon.

## The right-click menu

Right-click the clock for **Show Timers**, **Timer History**, **Settings…**, **Welcome Guide** and
**Quit Drag Timer**. Quit and the guide are also under **More** in the panel's footer.

## Where things are kept

Active timers, finished timers waiting for an answer, and history are stored on your Mac in
`~/Library/Application Support/DragTimer/`. There is no account and no cloud history. History is capped at 500 entries
or 90 days.

Timers are stored as the moment they end, so they stay correct across sleep, wake and a relaunch of the app.
