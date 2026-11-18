# Brag workspace: LibreWeave demo media

Captured 2026-11-17 from app source at **`5070fb1`** (Write is the full-width editor with no Layout segment highlighted, Document Mode, shared Format commands, table grid with 6 pt cell padding, code blocks and list gaps). Dark throughout. The only UI blue is `#2563EB`.

## Published files in `landing/media/`

| File | Spec |
| --- | --- |
| `libreweave-demo.mp4` | 18.0 s, 1920×1080, 30 fps (540 frames), H.264 High yuv420p + AAC 48 kHz stereo (peak −16 dBFS), `+faststart`, 2.5 MB |
| `libreweave-demo-poster.jpg` | 1280×720, frame at 8.2 s: Markdown source beside the Read rendering. Separate file; frame 0 of the video is the hook |
| `libreweave-demo-preview.gif` | 18 s, 600×338, 10 fps, loops, silent, 1.4 MB (180 frames). Built from the lossless render frames (not the MP4) with a 256-colour palette that includes exact `#2563EB` and its blends, no dithering. Embedded in the root README and linked to the MP4 |
| `libreweave-hero.png` | 1600×944, dark window, `orbit.tex` source and built PDF ("Built") |
| `libreweave-markdown.png` | 1600×944, light window, full-width **Write** with the format bar and Document Mode |
| `libreweave-latex-light.png` | 1600×944, light window, `orbit.tex` source and built PDF |

The landing page plays the MP4 in its existing `autoplay muted loop playsinline` video (no autoplay under Reduce Motion), with the poster. GitHub's README renderer strips `<video>` (confirmed with the GitHub Markdown API), so the root README embeds the GIF and links it to the MP4.

## The video

| Time | Scene | Footage |
| --- | --- | --- |
| 0–2.4 | Hook | Black. "Write the source." / "See the page." (`#2563EB`) |
| 2.4–10.2 | Markdown | **One continuous take.** Typing in full-width Write: `**clear light**` and `*no wind*` show their markers mid-word, then format. Document Mode → Read brings back the source beside the Pandoc rendering (grid table, MathML). Camera: zoom on the typed line, pull back, hold on source + Read, then zoom until only Read fills the frame. Caption: "Write it formatted. Read it rendered." |
| 10.2–15.6 | LaTeX | **One continuous take.** A sentence is typed, Build is pressed, Ready → Building… → Built, and the camera zooms into the PDF, where the typed sentence appears. Caption: "LaTeX, built on your Mac." |
| 15.6–18 | Outro | Current `landing/icon.svg` (58% weave), rendered in its dark-scheme treatment (white sheet) because the composition renders with `prefers-color-scheme: dark`; the same applies to the hook mark. Name, URL in `#2563EB`, and "App footage: LibreWeave's own views, recorded in real time off-screen." |

The camera zooms and pans over the takes. The footage itself is never cut, reordered or retimed. The score is a quiet stdlib synth at 100 BPM, with cuts on beats 4, 17 and 26.

## Capture method (off-screen, no visible app or focus change)

Capturing the shipped app on screen was ruled out: a background launch put its window on a hidden Space, where WebKit doesn't draw, and the app became active when that Space was shown. So:

1. `brag-output/work/harness-next`: a SwiftPM executable compiled from the app's own sources at the capture commit (`NativeLatex/App`, `Design`, `Integrations`, `MarkdownObjects`; the copy only drops `@main`). It hosts the real `EditorView` in an `NSWindow` that is never ordered in. The process uses activation policy `.prohibited`: no Dock icon, no menu bar, can't become active, no window on any display or Space. Appearance and the build owner token are launch arguments, so no preferences are written.
2. **Input:** `NSTextView.insertText` on the app's Write (or Source) view, 60–70 ms per character. Document Mode → Read selects the toolbar control's own Read segment. Build is the toolbar Build button's `performClick`, after writing the buffer to disk (what `NSDocument.saveEditedDocuments` does before every build).
3. **One call SwiftUI would make on screen:** a `.task` never fires in a window that is never shown, so the harness makes EditorView's `MarkdownObjects.attach(to:folder:bodyFont:bodyColor:)` call itself, with the app's exact arguments. `takes.sh` stops if that call changes.
4. **Frames:** captured continuously in real time at 3× (2400×1416, about 12–14 fps), so the zooms (up to 2.2×) stay sharp. Each frame is the window frame view via `cacheDisplay`. The Read `WKWebView` is drawn from its own `takeSnapshot` at its own rect. Timestamps are kept and frames held to 30 fps; nothing is sped up or interpolated.
5. Composition in `brag-output/work/comp/index.html` (camera keys in `CAM`), rendered frame by frame in headless Chrome with the dark colour scheme. Encoded with ffmpeg.

Rebuild: `brag-output/work/tools/takes.sh <commit>`, then `tools/final.sh 8.9`. Everything in `brag-output/` is git-ignored.

**Limits:** this is the app's code running in a harness, not a recording of the shipped app's window. No caret is drawn (the window is never key), and the typing is perfectly regular. The Format *menu* can't appear (no visible menu bar); the format bar does.

## Checks (final run)

- `ffprobe`: 540 frames, 18.000 s, 1920×1080, 30 fps; AAC 48 kHz stereo, mean −29.1 dB, peak −16.0 dB. GIF 180 frames, 18 s, 600×338.
- Frames pulled from the MP4 at 0.05, 1.5, 3.0, 4.3, 5.6, 7.0, 8.2, 9.0, 9.9, 11.0, 12.4, 13.6, 14.6, 15.2, 16.6 and 17.9 s, viewed at 900 px. Typing, live formatting, Document Mode → Read, the Read zoom (no source slivers), Building…/Built and the PDF zoom are legible, and captions stay in frame.
- **Blue:** `#0F2BFF`, `#2438FF`, `#0A84FF` and `#0071E3` (±8%): 0 px across every 6th frame and all files. Every strongly blue pixel in the three PNGs, the poster, 18 sampled render frames and 12 GIF frames lies on the `#2563EB` → black/white blend line: **0 off-brand pixels**. (The BB-8 switch's night-sky art, which `b9e51b4` keeps separate from the brand accent, sits below the scan's strong-blue threshold.)
- **MP4 encoding note:** browsers need H.264 4:2:0, and chroma subsampling shifts the colour of pixels on sharp `#2563EB`/white edges (outro icon threads, URL). A decoded outro frame has about 1,200 such edge pixels; the lossless render has none. Flat areas decode to `#2563EB`. The GIF and PNGs don't have this (lossless sources); the 4:4:4 alternative doesn't play in Safari.
- Landing (headless Chrome, local files; light, dark, 390 px phone): the MP4 autoplays, muted and looping (playing at 2.5 s, duration 18 s), with controls and the poster. Accent `rgb(37, 99, 235)`, BB-8 switch present, no horizontal scroll.
- README rendered through the GitHub Markdown API: hero, GIF (linked to the MP4), Write and LaTeX PNGs all resolve; no `<video>`.
- No app launched, no window shown, and no other app queried.
