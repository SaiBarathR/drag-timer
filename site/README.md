# Drag Timer website

The site at https://saibarathr.github.io/drag-timer/, built with [Astro](https://astro.build) into plain static
files. The only JavaScript on the pages is a few small scripts (theme, copy buttons, download links, the hero demo).

```sh
cd site
npm ci
npm run dev       # http://localhost:4321/drag-timer/
npm run build     # static site in site/dist
npm run preview   # serve site/dist
```

`.github/workflows/pages.yml` builds and deploys it on every push to `main` that touches `site/`, `docs/releases/`
or `Packaging/Info.plist`.

## Where the content comes from

| Page | Source |
| --- | --- |
| Home, Download | `site/src/pages/*.astro`, written from the repository `README.md` |
| Getting started, Timers, Presets and routines, Preferences, Keys and clicks | `site/src/guides/*.md` |
| Changelog | `docs/releases/v*.md`, rendered as they are, newest version first |
| Version number and minimum macOS | `Packaging/Info.plist`, read at build time (`src/lib/site.ts`) |
| Download links | The latest GitHub release, looked up in the browser; without JavaScript they open the releases page |

The copy follows the README and the release notes. When the app changes, change those first, then the pages and
guides here. Keys and clicks mirrors `WelcomeShortcutGroup.all` in `Sources/DragTimer/UI/WelcomeGuide.swift`.

The hero demo (`src/components/DragDemo.astro`) is an illustration, not the app. It uses the same ladder and snap
points as `DurationLadder` and `SnapGrid` in `Sources/DragTimer/Physics/DragPhysics.swift`, up to the default
4-hour maximum, with a shorter step so the whole ruler fits in the picture. Update it if the ladder changes.

## Design

Warm neutrals with the app icon's three colours: navy (`#14264B`), cream (`#F0EBDB`) and one coral accent
(`#F46F62`, the cord pulled out of the clock). Coral fills buttons with navy text on it; coral text on the light
background uses a darker shade (`--accent-text`) to keep 4.5:1 contrast. No purple and no gradients, including code
highlighting (`src/lib/code-themes.mjs` recolours GitHub's themes). Light and dark follow the system, with a toggle.

Every screenshot is of the app's dark appearance, so each sits on a navy panel (`.shot` in `src/styles/global.css`)
that looks deliberate in both themes.

## Screenshots and video

`public/images/*.webp` are captures of the real app made for the promo video (popover, name prompt, History,
Preferences tabs, Welcome Guide, menu-bar item), converted with `cwebp` at their 2× resolution and shown at half
size. `public/images/app-icon.webp` and the favicons come from `Packaging/AppIcon-master.png`.

`public/media/promo.mp4` is the 29-second promo, the one the README embeds, re-encoded to 1280×720 H.264 with
`+faststart`. `promo-poster.webp` is its title card. `public/og.png` is the 1200×630 social card.

The promo's music must be credited wherever the video is shown (`src/components/Video.astro` and the footer do):

> Music: "Blipotron" by Kevin MacLeod (incompetech.com), licensed under
> [Creative Commons: By Attribution 4.0](http://creativecommons.org/licenses/by/4.0/).

Icons are from [Lucide](https://lucide.dev) (ISC license), drawn inline at build time.
