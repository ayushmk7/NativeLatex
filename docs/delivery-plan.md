# Delivery plan and acceptance gates

Status: planning only · 2026-11-16. No app implementation is part of this pass.

## Workstreams

| Workstream | Plan | Implementation responsibility |
| --- | --- | --- |
| Art | [Art direction](workspaces/art/art-direction.md) | Icon and brand assets, native window mockups, color and contrast review. |
| UX | [UX plan](workspaces/ux/ux-plan.md) | Flows, menus, keyboard paths, empty/error states and accessibility checks. |
| Backend | [Architecture](workspaces/backend/architecture.md) | Swift app shell, file safety, compiler process, PDF preview, SyncTeX and release. |
| Integrations | [Integration plan](workspaces/integrations/integrations.md) | Conversion corpus, non-destructive DOCX/ODT exchange, provider feasibility. |

One coordinator keeps shared decisions in the [product plan](product-plan.md). Changes to document ownership, file safety and main window commands need cross-workstream review.

## Implementation order

| Gate | Deliverable | Proof required before moving on |
| --- | --- | --- |
| 0. Local prerequisites | Full Xcode selected; clean Swift macOS project; TeX detection checked | Build and launch a blank native window locally; detect current TeX paths and a simulated missing-tool state. |
| 1. Safe workspace editing | Folder windows, direct `.tex`/`.md` file open, tree, tabs, editor, save, recent folders | Finder/Open With selects the file; two folders open; undo works; external edits and dirty buffers cannot overwrite each other. |
| 2. Reliable render loop | Explicit TeX root, `latexmk`, diagnostics/log, PDFKit preview, cancel, stale badge, native Markdown preview | Single and multi-file TeX fixtures build; `.md` renders without TeX/Pandoc; error links work; cancel/failure leaves source and last good output safe. |
| 3. Native polish | Menus, shortcuts, keyboard/VoiceOver, dark/high-contrast layout, app icon | Complete first-PDF and fix-error tasks with keyboard and VoiceOver; narrow window stays usable. |
| 4. Power workflow | Outline, search, citation keys, images, SyncTeX, Xe/Lua profiles | Test nested source mapping, image insertion, bibliography and simultaneous workspace builds. |
| 5. File interchange | Pandoc-backed DOCX/ODT copy conversion | Review fidelity corpus in Word and LibreOffice; conversion report and original preservation verified. |
| 6. Connected options | Google Docs transfer; evaluate LibreTexts path | OAuth scope, sign-out, remote conflict, license and attribution tests; ship only proven actions. |

Gates 1–3 form the first useful local release. Gates 4–6 can follow without changing project files.

## Fixtures to prepare when implementation begins

- `article`: one `.tex` file with a title, section and equation.
- `notes`: one `.md` file with headings, links, list and code fence; code fence must display without running. A second Markdown fixture exercises images, tables and math with Pandoc available and missing.
- `paper`: root plus included section, image and BibTeX file.
- `thesis`: nested include paths and two plausible roots to test root choice.
- `broken`: missing package, bad reference, malformed environment and a previously successful PDF.
- `external-change`: a second editor modifies a clean and then a dirty file.
- `conversion`: math-heavy, citation-heavy and image-heavy samples for DOCX/ODT review.

Keep fixtures small and representative. Test trust boundaries and data-loss risks: save conflicts, build-generation ordering, process cancellation, diagnostic path resolution and conversion copy semantics. Avoid tests that only mirror static view code.

## Release check

Run on a Mac with TeX installed and a clean Mac without it. Verify `.md` preview works on both without Pandoc. Verify ordinary project files remain readable outside the app. Check signed/notarized launch, keyboard and VoiceOver paths, file-provider folders, multi-workspace builds and recovery from failed compilation. Record exact TeX and macOS versions. A cloud integration is never a dependency for local editing.
