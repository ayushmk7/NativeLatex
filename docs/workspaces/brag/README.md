# Brag workspace: product video and screenshot

Status: **capture method, composition and render pipeline ready; final recording waits for the owner to say the final app build is ready** (Backend is changing the Markdown preview pane controls). Updated 2026-11-17.

## Deliverables

| Asset | Published path | Budget | Used by |
| --- | --- | --- | --- |
| 18 s product video, 1920×1080, 30 fps, H.264 + AAC, `+faststart` | `landing/media/libreweave-demo.mp4` | ≤ 4 MB | landing `<video>`, README link |
| Poster (settled frame, also baked in as frame 0 of the MP4) | `landing/media/libreweave-demo-poster.jpg` | ≤ 200 KB | landing `poster=`, README |
| Real app screenshot (one window, Markdown source + preview) | `landing/media/libreweave-window.png` | ≤ 600 KB | README |

Everything is published from `landing/` because GitHub Pages serves only that folder. The README points at the same files, so there is one copy of each.

## Storyboard (18.0 s, ~100 BPM, cuts on beats)

| Time | Scene | On screen |
| --- | --- | --- |
| 0.0–3.0 | Hook | White. "Write the source. / See the page." (landing headline, blue second line) |
| 3.0–9.0 | Markdown | Real light-mode window, `field-notes.md`: a table row is typed and the Pandoc preview grows a row live. Caption: "Markdown, previewed as you type." |
| 9.0–14.4 | LaTeX | Real dark-mode window, `orbit.tex`: ⌘B, build badge, PDF appears. Caption: "LaTeX, built on your Mac." |
| 14.4–18.0 | Outro | App icon, "LibreWeave", "Native on Mac. Local by default.", `libreweave.ayushmadhav.com` |

No voiceover; quiet synthesized score (pad + pluck, peak −16 dBFS). Palette and type: landing tokens (`#0F2BFF` light, `#2438FF` dark fill, `#7A93FF` dark text; white/black surfaces; system sans 800). Captions only state what `main` does (see the facts table in [docs/README.md](../../README.md)). New pane controls are shown or mentioned only if they are in the final build.

## Content

Demo files are fictional: `field-notes.md` (a tide-pool survey) and `orbit.tex` ("Notes on a Quiet Orbit", author "A. Example"). No real names, paths or accounts appear on screen.

## Capture method (genuine app, window only)

1. Launch a separate instance of the final build: `open -g -n -a LibreWeave.app <file> --args -ApplePersistenceIgnoreState YES -appearanceMode light|dark`. The argument domain sets appearance without changing the owner's saved preference, and no other windows are restored.
2. Find that instance's window by **pid** (`CGWindowListCopyWindowInfo`, filtered to the pid), resize it to 800×450 pt through System Events, scoped to that pid. 800 pt is just above the 760 pt side-by-side breakpoint, so text stays legible when the video is shown ~900 px wide.
3. Record with ScreenCaptureKit, `SCContentFilter(desktopIndependentWindow:)`: the window's own pixels only, no desktop, no other apps, no cursor. Typing and ⌘B are sent only while that pid is frontmost.
4. Stills with `screencapture -l <windowID>`. Quit only that pid.
5. Compose in HTML (every frame a pure function of time, rendered with headless Chrome), encode with ffmpeg.

Validated 2026-11-17 against the current `main` build (still and 2 s recording of a background window). The tools and intermediates live in `brag-output/` (git-ignored).

## Embedding

- **Landing:** a `<video>` with `controls`, `muted`, `playsinline`, `preload="none"` and the poster, replacing the "Concept illustration" figure. Not autoplaying with sound.
- **README (GitHub):** GitHub strips `<video>` and shows `![](x.mp4)` as a broken image (checked with the GitHub Markdown API). The README uses the poster as a clickable image linked to the MP4 on the live site, plus a text link "Watch the 18-second demo", and the real window screenshot inline. The README does not claim an inline player.
