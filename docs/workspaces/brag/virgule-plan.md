# Brag plan: Virgule candidate (README and demo media)

**Update 2026-11-18:** implemented after the owner authorized the rebrand (see `docs/prompts/virgule-implementation.md`), with one change from this plan: media files keep their `libreweave-*` names for URL continuity instead of being renamed. Current state and checks: `README.md` in this folder.

**Status:** planning only. Virgule is a candidate name, not an approved rebrand. Nothing in this plan renames, re-records, publishes or deploys anything. Facts below were read from `main` at `840319f` plus this branch's unmerged `e16830c` (light demo cut).

## Name gate (blocks every public step)

- An iPhone/iPad news app named Virgule exists (App Store ID 1245101112), and a preliminary search found a Canadian VIRGULE trademark listing that mentions software. Neither has been reviewed; this plan does not treat the name as cleared or the listing as applying to this app.
- **Public-rename hold:** no README, landing media, video, GIF, poster or share copy carrying "Virgule" is committed to `main`, pushed, or posted until the coordinator records a passed name review.
- **Reversible internal prototype:** all Virgule renders go to the git-ignored `brag-output/virgule/` folder (already ignored via `brag-output/`). Files keep their current `libreweave-*` names on disk until the gate passes, so a rejected name leaves no trace in git or on the site.
- **Fallback:** the brand text in the media comes from one place (see "One source for brand text"), so a different name is a re-render with a new value, not new capture work. If no rename happens, the current LibreWeave media stays as is.

## Current touchpoints

### Brand burned into pixels (needs re-render, not a text edit)

| Asset | Where the brand appears | Source |
| --- | --- | --- |
| `landing/media/libreweave-demo.mp4` (dark, 18 s) | Hook: icon + "LibreWeave" mark. Outro: name, `libreweave.ayushmadhav.com`, "App footage: LibreWeave's own views…" | `brag-output/work/comp/index.html` lines 31, 48, 50, 52 |
| `landing/media/libreweave-demo-light.mp4` (`e16830c`, not on `main`) | Same as above, light | same comp |
| `landing/media/libreweave-demo-preview.gif` | Same hook and outro frames | built from render frames by `work/tools/final.sh` |
| `landing/media/libreweave-demo-poster.jpg`, `…-poster-light.jpg` | Frame at 8.2 s (Markdown source + Read). Expected brand-free; verify | `final.sh` |
| `libreweave-hero.png`, `libreweave-markdown.png`, `libreweave-latex-light.png` | App window footage only. Expected brand-free (document windows show file names, not the app name); verify | `final.sh` from harness shots |
| Hook/outro icon | `landing/icon.svg`, copied to `comp/assets/icon.svg` | Art workspace owns the icon |

App footage itself: the harness (`brag-output/work/harness-next`) compiles the app's own sources, including `LibreWeaveApp.swift`. Strings with "LibreWeave" in `NativeLatex/App` are error/panel messages (`BuildService.swift:31,33`, `Conversions.swift:19,103`, `TextDocument.swift:16`, `LibreWeaveApp.swift:334`, `MarkdownPreview.swift:92`) that the current takes never show. Attributed-string keys in `MarkdownWriter.swift:8–17` are internal and never visible.

### Text and references (plain edits)

| File | Touchpoint |
| --- | --- |
| `README.md` | `<h1>`, icon alt, every image alt, "LibreWeave" in body copy (≈10 places), `libreweave.ayushmadhav.com` demo links (lines 15–16), `-scheme LibreWeave` and `LibreWeave.app` in the build block, "Repository… named NativeLatex; the app is LibreWeave" line, `.libreleaf-build` folder name |
| `README.md` image paths | `landing/media/libreweave-*.png/gif` (lines 11, 15, 23, 29) |
| `landing/index.html:73–78` | `poster=`, `<source src=>`, fallback link and aria-labels name the media files and the brand (Landing owns the page; Brag owns the file names it points at) |
| `landing/script.js` (`e16830c`) | Swaps dark/light MP4 and poster by theme: file names hard-coded |
| `docs/workspaces/brag/README.md` | Media spec table, storyboard, captions, rebuild commands |
| `brag-output/share-copy.txt`, `brag-output/final/CAPTURE.md` | Share text and capture notes (git-ignored, but they are what gets pasted publicly) |
| `brag-output/work/tools/final.sh:15–25` | Output file names `libreweave-demo*.mp4/jpg`, `libreweave-*.png` |
| `brag-output/work/tools/takes.sh:12,14` | Patches and greps `Harness/LibreWeaveApp.swift`; breaks if Backend renames that file or the `App` struct |
| `brag-output/work/tools/capture.sh` | Takes a `LibreWeave.app` path (on-screen method, already ruled out; comments only) |

### Embedded metadata

- Both MP4s carry only `major_brand`/`encoder` tags; no title/comment. PNG/JPG/GIF have no title, comment or software tags (checked with `ffprobe` and `exiftool`). No stale brand in metadata today; the plan keeps it that way.
- `landing/index.html` has no `og:image`/`og:video`/`twitter:*` tags today. If Landing adds them, they reference these files and must follow the same names.

## Smallest complete change set (after the gate passes)

1. **One source for brand text.** Replace the four literals in `comp/index.html` with a `BRAND` / `URL` pair read from one place (a JS constant or `final.sh` env var). Only the hook mark, outro name, outro URL and footnote change. Storyboard, camera keys (`CAM`), score, timings and footage stay identical.
2. **Re-render, don't re-capture.** The existing lossless takes (`rec-md4`, `rec-tex4`, `*-light`) contain no brand, so dark and light cuts render from them with the new comp. Re-capture is needed only if Backend/UX change any string or chrome visible in the takes (window title, toolbar labels, Document Mode/Build labels). Decide by diffing visible UI strings between `5070fb1` and the rename commit.
3. **Icon.** Use whatever `landing/icon.svg` Art ships (single mark, no nested box, adaptive light/dark). Hook and outro render in the dark scheme, as now; the light cut uses the light treatment.
4. **Rename the media files** `libreweave-*` → `<name>-*` in `final.sh`, then update every reference in one commit: `README.md`, `landing/index.html`, `landing/script.js`, `docs/workspaces/brag/README.md`. Old names are not kept as duplicate binaries (repo size); the old site's media URLs are Landing's redirect problem (see Dependencies).
5. **README copy.** Swap the name in headings, body and alt text. Keep the description multi-format: "A native Mac editor for LaTeX, Markdown and plain text…" (the app opens and edits more than one format; it is not a viewer). Build block uses whatever scheme and `.app` name Backend actually ships; until then keep `LibreWeave`. The `.libreleaf-build` line changes only if Backend migrates that folder. Demo links point at the hostname Landing actually serves.
6. **Share copy and capture notes** updated in `brag-output/` (local only).
7. **Brag README** updated: spec table, captions, new file names, the commit the media was rendered from.

Not in scope: re-shooting the storyboard, new scenes, changing the 18 s length, any app code.

## Sequencing and dependencies

1. Name review passes (coordinator). Nothing public before this.
2. Merge `e16830c` (light cut) to `main` first, or drop it; the rename must touch both cuts or neither.
3. Art delivers the final icon SVG and wordmark decision (does the hook use text, a wordmark image, or icon only?).
4. Backend decides the scheme, `.app` name, App struct/file name (affects `takes.sh` greps) and whether `.libreleaf-build` migrates.
5. UX decides any visible UI copy changes. If any appear in the takes → re-capture with `takes.sh <commit>` (off-screen harness, `.prohibited` activation policy, no prefs written; see "Capture method" in the brag README).
6. Landing confirms the hostname and whether old `libreweave.ayushmadhav.com/media/*.mp4` URLs redirect.
7. Brag renders into `brag-output/virgule/`, runs the checks below, then one commit renames files and updates all references together.
8. Landing deploys; README links switch only after the new URLs resolve.

## Validation that proves completion

- **No stale brand in any distributable asset:** OCR (e.g. `tesseract` or Vision) over every 6th frame of both MP4s, all GIF frames, both posters and the three PNGs finds no "LibreWeave"/"libreweave"; frames at the brag README's 16 sample times reviewed by eye at 900 px.
- **Metadata:** `ffprobe -show_entries format_tags` and `exiftool` on every file show no old brand (and no new title tag unless chosen deliberately).
- **References:** `git grep -n -i libreweave -- README.md landing docs/workspaces/brag` returns only intentional history notes; every `landing/media/*` path in README, `index.html` and `script.js` exists.
- **Footage unchanged:** frame-diff the new render against the old one outside the hook (0–2.4 s) and outro (15.6–18 s): identical except for icon/text regions.
- **Specs held:** 540 frames, 18.000 s, 1920×1080, 30 fps, H.264 4:2:0 `+faststart`, AAC 48 kHz peak −16 dBFS; GIF 180 frames 600×338.
- **One blue:** `bluescan.py` reports 0 off-brand pixels against `#2563EB` across all files (same thresholds as the current run).
- **README render:** GitHub Markdown API render resolves hero, GIF, Write and LaTeX images; GIF links to a live MP4.
- **Landing:** `landing-check.mjs` in light, dark and 390 px: correct cut per theme, autoplay muted loop, poster, BB-8 switch carries time/play state.
- No app launched, no window shown during any capture.

## Migration and rollback risks

| Risk | Mitigation |
| --- | --- |
| Name rejected after media rendered | Renders live only in `brag-output/virgule/`; nothing to revert in git |
| README links to MP4 URLs that 404 after a hostname change | README updated only after Landing's new URLs resolve; old URLs redirected or kept by Landing |
| File rename lands without reference updates (broken images on GitHub and site) | Rename + all references in one commit; reference check above |
| Dark and light cuts drift (one renamed, one not) | Both cuts render from one comp in one `final.sh` run |
| `takes.sh` breaks on Backend's rename of `LibreWeaveApp.swift` | Update the two greps to the new file/struct name in the same pass; re-capture would otherwise fail its safety check |
| Old media persists in forks, caches, social previews | Accept; no OG tags exist today, so no cached preview images carry the old name beyond the README GIF |
| Footage shows old UI strings if app copy changes after render | Render after UX copy freezes; re-capture if visible strings changed |
| Rollback after going public | Revert the single rename commit; old `libreweave-*` files return from git history; Landing restores the old host |

## Decisions for the coordinator

1. Has the name review passed, and who signs it off?
2. Merge or drop `e16830c` (light cut) before the rename?
3. Hook: icon + text name (as now), a wordmark image from Art, or icon only?
4. Media file prefix: `virgule-*`, or a brand-neutral prefix (`demo.mp4`, `hero.png`) so a future rename needs no file moves? Recommendation: brand-neutral, it removes step 4 for every later rename.
5. Outro URL: which hostname, and is it live before the media ships?
6. README description wording that covers LaTeX, Markdown and plain text without listing every format.
7. Keep the README's "Repository… named NativeLatex" line, given the repo name itself is out of scope here?
