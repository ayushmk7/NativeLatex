# Brag workspace: Virgule demo media

Re-captured 2026-11-18 from app source at **`81ad340`** (the Virgule rename; first captured 2026-11-17 at `5070fb1`, and no visible UI in these takes changed in between). The files keep their `libreweave-*` names so existing URLs keep working. The app UI shown: Write is the full-width editor with no Layout segment highlighted, Document Mode, shared Format commands, table grid with 6 pt cell padding, code blocks and list gaps. The demo exists in a dark and a light cut with the same timeline. The only UI blue is `#2563EB`.

## Published files in `landing/media/`

| File | Spec |
| --- | --- |
| `libreweave-demo.mp4` | 18.0 s, 1920×1080, 30 fps (540 frames), H.264 High yuv420p + AAC 48 kHz stereo (peak −16 dBFS), `+faststart`, 2.5 MB |
| `libreweave-demo-poster.jpg` | 1280×720, frame at 8.2 s: Markdown source beside the Read rendering. Separate file; frame 0 of the video is the hook |
| `libreweave-demo-light.mp4` | Light cut: same specs, storyboard, camera and score, from takes recorded in light appearance with the same timings. 2.7 MB |
| `libreweave-demo-poster-light.jpg` | 1280×720, light frame at 8.2 s |
| `libreweave-demo-preview.gif` | 18 s, 600×338, 10 fps, loops, silent, 1.4 MB (180 frames). Built from the lossless render frames (not the MP4) with a 256-colour palette that includes exact `#2563EB` and its blends, no dithering. Embedded in the root README and linked to the MP4 |
| `libreweave-hero.png` | 1600×944, dark window, `orbit.tex` source and built PDF ("Built") |
| `libreweave-markdown.png` | 1600×944, light window, full-width **Write** with the format bar and Document Mode |
| `libreweave-latex-light.png` | 1600×944, light window, `orbit.tex` source and built PDF |

The landing page has one `autoplay muted loop playsinline` video per theme (no autoplay under Reduce Motion), each with its own poster. CSS shows the one matching the page theme; only that one loads. Hovering or focusing the BB-8 switch starts loading the other, and a switch carries over the time, play state and sound, so the footage just changes appearance. Without JavaScript the dark cut plays. GitHub's README renderer strips `<video>` (confirmed with the GitHub Markdown API), so the root README embeds the GIF and links it to the MP4 in the repository (`landing/media/libreweave-demo.mp4`), which is the current cut even before the site redeploys.

## The video

| Time | Scene | Footage |
| --- | --- | --- |
| 0–2.4 | Hook | Black. "Write the source." / "See the page." (`#2563EB`) |
| 2.4–10.2 | Markdown | **One continuous take.** Typing in full-width Write: `**clear light**` and `*no wind*` show their markers mid-word, then format. Document Mode → Read brings back the source beside the Pandoc rendering (grid table, MathML). Camera: zoom on the typed line, pull back, hold on source + Read, then zoom until only Read fills the frame. Caption: "Write it formatted. Read it rendered." |
| 10.2–15.6 | LaTeX | **One continuous take.** A sentence is typed, Build is pressed, Ready → Building… → Built, and the camera zooms into the PDF, where the typed sentence appears. Caption: "LaTeX, built on your Mac." |
| 15.6–18 | Outro | The Virgule slash from `landing/icon.svg` at `81ad340`, with its sheet inverted for contrast: white sheet in the dark cut, black sheet in the light cut; the hook mark (icon + "Virgule") uses the same treatment. "Virgule", "Native on Mac. Local by default.", `virgule.ayushmadhav.com` in `#2563EB`, and "App footage: Virgule's own views, recorded in real time off-screen." |

The camera zooms and pans over the takes. The footage itself is never cut, reordered or retimed. The score is a quiet stdlib synth at 100 BPM, with cuts on beats 4, 17 and 26.

## Capture method (off-screen, no visible app or focus change)

Capturing the shipped app on screen was ruled out: a background launch put its window on a hidden Space, where WebKit doesn't draw, and the app became active when that Space was shown. So:

1. `brag-output/work/harness-next`: a SwiftPM executable compiled from the app's own sources at the capture commit (`NativeLatex/App`, `Design`, `Integrations`, `MarkdownObjects`; the copy only drops `@main`). It hosts the real `EditorView` in an `NSWindow` that is never ordered in. The process uses activation policy `.prohibited`: no Dock icon, no menu bar, can't become active, no window on any display or Space. Appearance and the build owner token are launch arguments, so no preferences are written.
2. **Input:** `NSTextView.insertText` on the app's Write (or Source) view, 60–70 ms per character. Document Mode → Read selects the toolbar control's own Read segment. Build is the toolbar Build button's `performClick`, after writing the buffer to disk (what `NSDocument.saveEditedDocuments` does before every build).
3. **One call SwiftUI would make on screen:** a `.task` never fires in a window that is never shown, so the harness makes EditorView's `MarkdownObjects.attach(to:folder:bodyFont:bodyColor:)` call itself, with the app's exact arguments. `takes.sh` stops if that call changes.
4. **Frames:** captured continuously in real time at 3× (2400×1416, about 12–14 fps), so the zooms (up to 2.2×) stay sharp. Each frame is the window frame view via `cacheDisplay`. The Read `WKWebView` is drawn from its own `takeSnapshot` at its own rect. Timestamps are kept and frames held to 30 fps; nothing is sped up or interpolated.
5. Composition in `brag-output/work/comp/index.html` (camera keys in `CAM`), rendered frame by frame in headless Chrome with the dark colour scheme. Encoded with ffmpeg.

Rebuild: `brag-output/work/tools/takes.sh <commit>`, then `tools/final.sh 8.2`. Brand text lives in four literals in `comp/index.html` (hook mark, outro name, URL, footnote); `comp/assets/icon.svg` is `landing/icon.svg` with the sheet colours swapped. The light cut: record `rec-md4-light` and `rec-tex4-light` with the same `takes.sh` lines in `light`, then `THEME=light tools/final.sh 8.2` (the composition takes its colours and frame folders from `prefers-color-scheme`). Everything in `brag-output/` is git-ignored.

**Limits:** this is the app's code running in a harness, not a recording of the shipped `Virgule.app` window. No caret is drawn (the window is never key), and the typing is perfectly regular. The Format *menu* can't appear (no visible menu bar); the format bar does.

## Checks (Virgule run, 2026-11-18, app source `81ad340`)

- `ffprobe`, both cuts: 540 frames, 18.000 s, 1920×1080, 30 fps, H.264 High yuv420p, `moov` before `mdat` (`+faststart`); AAC LC 48 kHz stereo, mean −29.1 dB, peak −16.0 dB. GIF 180 frames, 18 s, 600×338, loops.
- Frames from both MP4s at 0.05, 1.5, 3.0, 4.3, 5.6, 7.0, 8.2, 9.0, 9.9, 11.0, 12.4, 13.6, 14.6, 15.2, 16.6 and 17.9 s, viewed as sheets: hook mark and outro show the slash icon and "Virgule"; typing, live formatting, Document Mode → Read, Building…/Built and the PDF zoom are legible.
- **OCR** (`tesseract`) over every 6th frame of both MP4s (90 + 90), all 180 GIF frames, both posters and the three PNGs: no "LibreWeave"/"libre"/"weave"; "Virgule" and `virgule.ayushmadhav.com` read in hook and outro frames.
- **Metadata:** MP4 tags are `major_brand`/`encoder`/handler only; JPEG comment is the encoder string; PNG `eXIf` holds only size/resolution; no file contains "libre", "weave" or "virgule" bytes.
- **Re-capture:** the dark poster and the three README PNGs came out byte-identical to the `5070fb1` files, so they carried no old icon or name and are unchanged in git.
- **Blue** (`bluescan.py`): 0 off-brand pixels in the three PNGs and the dark poster; settled hook/outro frames are on the `#2563EB` → black/white blend line. Flagged pixels are fade-in frames where the slash sits on a half-opaque white sheet (e.g. `#728BC0` ≈ 0.39 brand + 0.39 white + black), one 1 px BB-8 edge in the LaTeX take, and 2 px of JPEG noise in the light poster.
- **Playback:** `landing-check.mjs` (headless Chrome, local files; light, dark, 390 px, Reduce Motion) passes with and without `--autoplay-policy=no-user-gesture-required`: the theme's cut autoplays muted and looping, the other stays paused, a BB-8 switch keeps time (+0.33–0.36 s over 0.4 s) and play state, Reduce Motion stays at 0. AVFoundation reports both MP4s playable (Safari's decoder path); WebKit itself was not run.
- No app launched, no window shown (harness activation policy `.prohibited`, window never ordered in), no other app queried.
