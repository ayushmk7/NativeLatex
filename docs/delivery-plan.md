# Delivery plan and acceptance gates

Status: gates in progress · revised 2026-11-17 · Mac only. Gate 0 is mostly met: the `LibreLeaf` scheme builds and its tests pass on this Mac; a missing-TeX run has not been checked. Gate 1 is partial: direct file open, edit and save work one file per window; folder windows, tree, tabs and recent folders are not built. Gate 2 is partial: a local `latexmk` build, log, diagnostics, PDF preview, cancel, stale badge and a basic Markdown preview exist, without root selection. Details: [Implemented on main](README.md#implemented-on-main-checked-2026-11-17).

## Workstreams

| Workstream | Plan | Implementation responsibility |
| --- | --- | --- |
| Art | [Art direction](workspaces/art/art-direction.md) | Icon and brand assets, native window mockups, color and contrast review. |
| UX | [UX plan](workspaces/ux/ux-plan.md) | Flows, menus, keyboard paths, empty/error states and accessibility checks. |
| Backend | [Architecture](workspaces/backend/architecture.md) | Swift app shell, file safety, compiler process, PDF preview, SyncTeX and release. |
| Integrations | [Integration plan](workspaces/integrations/integrations.md) | Conversion corpus, non-destructive DOCX/ODT exchange, provider feasibility. |
| Landing | [Landing plan](workspaces/landing/landing-plan.md) | Static page, light/dark design, honest development status, Vercel preview. |
| Release | [Deployment plan](deployment-plan.md) | Developer ID signing, notarization, AWS artifact hosting, optional Vercel landing page. |

One coordinator keeps shared decisions in the [product plan](product-plan.md). Changes to document ownership, file safety and main window commands need cross-workstream review.

## Implementation order

| Gate | Deliverable | Proof required before moving on |
| --- | --- | --- |
| 0. Local prerequisites | Full Xcode selected; clean Swift macOS project; TeX detection checked | Build and launch a blank native window locally; detect current TeX paths and a simulated missing-tool state. |
| 1. Safe workspace editing | Folder windows, direct `.tex`/`.md` file open, tree, tabs, editor, save, recent folders | Finder/Open With selects the file; two folders open; undo works; external edits and dirty buffers cannot overwrite each other. |
| 2. Reliable render loop | Explicit TeX root, `latexmk`, diagnostics/log, PDFKit preview, cancel, stale badge, native Markdown preview | Single and multi-file TeX fixtures build; `.md` renders without TeX/Pandoc; error links work; cancel/failure leaves source and last good output safe. |
| 3. Native polish | Menus, shortcuts, keyboard/VoiceOver, black/white light and dark appearances, royal-blue accent, BB-8 inspired switch, app icon | Complete first-PDF and fix-error tasks with keyboard and VoiceOver; switch follows macOS until overridden and respects Reduce Motion. |
| 4. Mac release | Developer ID archive, notarized and stapled ZIP, AWS download; optional Vercel landing page | Verify the downloaded bytes on a clean Mac, including TeX-present and TeX-absent behavior; publish checksum and release notes. |
| 5. Power workflow | Outline, search, citation keys, images, SyncTeX, Xe/Lua profiles | Test nested source mapping, image insertion, bibliography and simultaneous workspace builds. |
| 6. File interchange | Pandoc-backed DOCX/ODT reviewable copies | The [local test](research/conversion-test-2026-11-17.md) exposed silent reference/citation losses; repeat with Word and real user files, show conversion report, and preserve originals. |
| 7. Connected options | Owner-only Google Docs/OneDrive transfer; evaluate LibreTexts path | OAuth scope, sign-out, failed-transfer recovery, license and attribution tests; ship only proven actions. |

Gates 1–4 form the first useful Mac release. Gates 5–7 can follow without changing project files. There is no iPhone or iPad track.

## Fixtures to prepare when implementation begins

- `article`: one `.tex` file with a title, section and equation.
- `notes`: one `.md` file with headings, links, list and code fence; code fence must display without running. A second Markdown fixture exercises images, tables and math with Pandoc available and missing.
- `paper`: root plus included section, image and BibTeX file.
- `thesis`: nested include paths and two plausible roots to test root choice.
- `broken`: missing package, bad reference, malformed environment and a previously successful PDF.
- `external-change`: a second editor modifies a clean and then a dirty file.
- `conversion`: the Integrations package tests already read `docs/research/conversion-fixtures` directly. Start with the [tested samples](research/conversion-test-2026-11-17.md), then add math-heavy, citation-heavy and image-heavy user documents for DOCX/ODT review.

Keep fixtures small and representative. Test trust boundaries and data-loss risks: save conflicts, build-generation ordering, process cancellation, diagnostic path resolution and conversion copy semantics. Avoid tests that only mirror static view code.

## Release check

Run on a Mac with TeX installed and a clean Mac without it. Verify `.md` preview works on both without Pandoc. Verify ordinary project files remain readable outside the app. Check the downloaded signed/notarized ZIP, keyboard and VoiceOver paths, file-provider folders, multi-workspace builds and recovery from failed compilation. Test both appearances and the BB-8 switch with Reduce Motion and increased contrast. A cloud integration is never a dependency for local editing.
