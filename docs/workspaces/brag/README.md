# Brag workspace: LibreWeave demo capture (2026-11-17)

## Published files in `landing/media/`

| File | What |
| --- | --- |
| `libreweave-demo.mp4` | 18.0 s, 1920×1080, 30 fps (540 frames), H.264 + AAC 48 kHz stereo, `+faststart`, 2.8 MB |
| `libreweave-demo-poster.jpg` | 1280 px poster, frame at 13.75 s (LaTeX source and built PDF). Not baked into the video; frame 0 is the hook |
| `libreweave-demo-preview.gif` | 18 s, 640×360, 6 fps, 1.1 MB silent moving preview embedded in the root README; click it for the MP4 with sound |
| `libreweave-hero.png` | dark window, `orbit.tex` + built PDF |
| `libreweave-markdown.png` | light window, source + Write mode with the only brand blue `#2563EB` |
| `libreweave-latex-light.png` | light window, `orbit.tex` + built PDF |

## What the footage is

Each app scene is **one continuous real-time take**, with no cuts inside it:

- **Markdown (2.4–9.6 s in video, 7.2 s of take):** a new table row and then a line with math are typed into the source pane. The app's own Pandoc Read preview adds the row when typing pauses, then renders the fraction as MathML. (The app cancels a pending render on each keystroke, so the preview updates at pauses. That is the app's real behaviour.)
- **LaTeX (9.6–15.6 s, 6.0 s of take):** a sentence is typed into `orbit.tex`, then Build is pressed. The toolbar badge goes Ready → Building… (spinner) → Built, and the PDF built by `latexmk` appears, containing the typed sentence.

## Exact capture method

Real on-screen capture of the shipping app was ruled out. A background `open -g` launch put its window on a hidden Space, where WebKit doesn't draw, and the instance became active once that Space was shown. That breaks "never touch the user's screen". So:

1. **Harness:** `brag-output/work/harness`, a SwiftPM executable compiled from the app's own sources at `main` **ff854ac** (`NativeLatex/App`, `Design`, `Integrations`; the copy only drops `@main`). It hosts the real `EditorView` in an `NSWindow` that is **never ordered in**. The process uses activation policy `.prohibited`: it has no Dock icon, no menu bar, can't become active, and has no window on any display or Space. Appearance and the build owner token are launch arguments, so no preferences are written.
2. **Input:** `NSTextView.insertText(_:replacementRange:)` on the app's Source view, one character every 70–85 ms, with 0.9 s pauses after lines. This is the text system's normal typing path (delegate → binding → preview), not a text swap. **Build** is the toolbar Build button's own `performClick`. Just before it, the harness writes the buffer to disk, standing in for `NSDocument.saveEditedDocuments`, which the app runs before every build (the harness has no NSDocument).
3. **Frames:** captured continuously in real time (~18–19 fps). Each frame is the window frame view (title bar, toolbar, panes, status bar) drawn with `cacheDisplay` at 2×. The Markdown Read pane is a `WKWebView`, which `cacheDisplay` can't draw, so its own `takeSnapshot` is drawn into the same frame at that view's own rectangle.
4. **Timing:** frames keep their capture timestamps and become 30 fps by holding each frame until the next one (ffmpeg concat with per-frame durations). Nothing is sped up, reordered or interpolated.
5. **Composition:** `brag-output/work/comp/index.html` (hook, two dark-mode takes with zooms over the continuous footage, outro) rendered frame by frame in headless Chrome, then a quiet synthesized score. The icon source came from `main` **9bc4b10**. The outro says: "App footage: LibreWeave's own views, recorded in real time off-screen."

**Limits, stated plainly:** this is the app's code and views running in a harness process, not a recording of the shipped `LibreWeave.app` window. No text cursor is drawn, because the window is never key (it can't be, without activation). The scripted typing is perfectly regular.

## Checks run

- `ffprobe`: 540 frames, 18.000 s, 1920×1080, 30 fps, AAC stereo, peak −16 dBFS.
- Frames pulled from the MP4 at 0, 1.2, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0, 13.2, 14.6 and 16.8 s, viewed at 900 px wide. Typing progress, preview row, math, Building…, Built and the PDF are all visible. Captions fit inside the frame.
- The app, icon and composition sources use one brand blue, `#2563EB`. Old blue values are absent from the README PNGs. A few near matches in compressed video frames are antialiased edges of `#2563EB`; one poster pixel comes from BB-8's original night-sky illustration, which is separate from the brand accent.
- No app was launched and no window was put on screen. The harness can't activate, and no other app was queried or captured.
- The capture harness did not edit landing or app source; the orchestrator copied the finished media into `landing/media/`.

GitHub's README renderer removes ordinary `<video>` tags for repository MP4 files (confirmed with the GitHub Markdown API). The root README embeds the animated GIF so the demonstration moves in place, and links it to the full MP4. The landing page uses the MP4 as an autoplaying, muted loop with native controls for sound.
