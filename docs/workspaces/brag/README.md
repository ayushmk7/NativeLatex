# Brag workspace: product video and screenshots

Status: **done** 2026-11-17. Media is from `main` at `b58a9e6` (Read/Write in the toolbar), the source of the final `dist/LibreWeave-current.app`.

## Published assets (`landing/media/`)

| File | What | Size | Used by |
| --- | --- | --- | --- |
| `libreweave-demo.mp4` | 18.0 s, 1920×1080, 30 fps, H.264 + AAC, `+faststart` | 3.6 MB | landing `<video>`, README link |
| `libreweave-demo-poster.jpg` | settled frame at 8.4 s (Markdown Write), 1280 px | 80 KB | landing `poster`, README |
| `libreweave-hero.png` | dark window, `orbit.tex` source + built PDF | 167 KB | README hero |
| `libreweave-markdown.png` | light window, `field-notes.md` source + Write mode | 129 KB | README |
| `libreweave-latex-light.png` | light window, `orbit.tex` source + built PDF | 153 KB | README |

Pages publishes only `landing/`, so the README links to the same files (one copy each).

## Storyboard (18.0 s, ~100 BPM, cuts on beats)

| Time | Scene | On screen |
| --- | --- | --- |
| 0.0–3.0 | Hook | White. "Write the source. / See the page." Frame 0 is this scene; there is no poster frame baked into the video. |
| 3.0–9.0 | Markdown | Light window in Source Only, then (4.8 s, 0.1 s near-cut) Source and Preview with Write selected. Caption: "Markdown you can read and write." |
| 9.0–14.4 | LaTeX | Dark window, Ready and "No PDF yet", then (10.8 s) Built with the PDF. Caption: "LaTeX, built on your Mac." |
| 14.4–18.0 | Outro | App icon, "LibreWeave", "Native on Mac. Local by default.", `libreweave.ayushmadhav.com` |

There's no voiceover; the score is a quiet stdlib synth (pad + pluck, −16 dBFS peak). Each scene shows two settled states of the real app. No typing is shown or claimed.

## How the screenshots were made (headless, nothing on screen)

Capturing a live app window was dropped. A background `open -g` launch of the final build put its window on a Space that wasn't showing, where WebKit doesn't draw, and the instance later turned up active. The owner's screen must not change, so:

1. `brag-output/work/harness` is a SwiftPM executable that compiles the app's own sources (`NativeLatex/App`, `Design`, `Integrations` from `b58a9e6`; only `@main` removed in the copy) and hosts the real `EditorView` in an `NSWindow` that is **never ordered in**. The process uses activation policy `.prohibited`: it has no Dock icon and can't become active. Appearance and the build owner token are passed as launch arguments, so no preferences are written.
2. The window frame view (title bar, toolbar and content) is drawn with `cacheDisplay` at 2×.
3. Real controls are driven in-process: the toolbar Layout control (Source Only) and the toolbar Read/Write control (Write). **Build** is the toolbar button's own `performClick`, so the app's `BuildService` runs `latexmk` and the PDFKit preview shows the result.
4. **Write pane composite:** offscreen, SwiftUI left the Write container empty: its shared scroll view was moved into a container that never got attached. The harness creates the app's own `WritingHandle`, takes its configured scroll view (styled by the app's `MarkdownStyler`), and attaches it to that container, as `HandleTextView.makeNSView` does. Then the whole window renders in one pass. These are real app components; no UI is drawn by hand.
5. The **Read** view (WebKit, Pandoc HTML) doesn't draw offscreen, so no shot shows it. Its tables, math and footnotes are described in copy only.
6. Corners are rounded (20 px alpha mask) for presentation.

At 640 pt wide, the toolbar shows Layout, Read/Write and BB-8 with no overflow (Convert is left out by design; File ▸ Convert remains).

## Content

Demo files are fictional: `field-notes.md` (tide pool notes, a link to `example.org`) and `orbit.tex` ("Notes on a Quiet Orbit", "A. Example"). Source lines are kept at 37 characters or fewer, so the source pane doesn't wrap. No real names, paths or accounts appear.

## Embedding

- **Landing:** a `<video>` with `controls`, `playsinline`, `preload="none"` and the poster. No `autoplay` and no `muted`: the music plays when a visitor presses Play. Page load fetches only the 80 KB poster.
- **README:** `docs/README.md` is the product page (the status inventory moved to [docs/status.md](../../status.md)). GitHub strips `<video>` and shows `![](x.mp4)` as a broken image (checked with the GitHub Markdown API), so the README uses the poster as a clickable image linked to the MP4 on the live site, plus a "Watch the 18-second demo" link. It doesn't claim an inline player. The links work once this branch is merged and Pages redeploys.

## Rebuild

Everything is in `brag-output/` (git-ignored): `work/harness` (render the stills), `work/comp/index.html` (composition; each frame is a pure function of time), `work/tools/render.mjs` (headless Chrome frames), `work/tools/music.py`, `work/tools/build.sh` (encode, poster).
