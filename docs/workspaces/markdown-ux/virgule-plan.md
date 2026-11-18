# Virgule candidate: Markdown UX plan

Status: planning only, 2026-11-18. Virgule is a candidate name, not an approved rebrand. Nothing here renames code, assets, bundle identifiers, URLs or releases. Facts below were read from `main` at `840319f`; the Herdr `markdown-ux` branch lags it.

## Name gate (applies to everything below)

- **Public-rename hold.** An iPhone/iPad news app is already called Virgule (App Store ID 1245101112), and a preliminary search found a Canadian VIRGULE trademark listing that mentions software. Neither has been reviewed. Do not treat the name as cleared or the listing as applicable. No public Markdown screenshot, caption or help text says "Virgule" until the coordinator records a passed name review.
- **Reversible internal prototype.** Markdown UX needs no Markdown-specific rename to prototype Virgule (see Finding 1). An internal build that changes only the product display name (Backend's area) already shows the candidate everywhere Markdown surfaces the app name. Reverting that one build setting undoes it.
- **Fallback if Virgule is rejected.** Keep LibreWeave, or swap in another name the same way. Step 1 below is brand-neutral, so it ships unchanged under any name.

## Finding 1: Markdown copy is already brand-free

The Markdown names users see don't include the app name, and none of them should change:

| Surface | Current text | Location |
| --- | --- | --- |
| Toolbar mode picker | **Document Mode**: **Read** / **Write**, its help text, accessibility label "Document Mode" | `NativeLatex/App/LibreWeaveApp.swift:213-219` |
| View menu | Source Only / Source and Preview / Preview Only (⌥⌘1–3), Toggle Preview (⌥⌘P), **Write** toggle (⌥⌘E) | `NativeLatex/App/LibreWeaveApp.swift:450-470` |
| Format menu and format bar | Command titles/help shared by both; disabled text "Formatting is available in Markdown documents." | `NativeLatex/App/LibreWeaveApp.swift:483-510`, `NativeLatex/App/MarkdownWriter.swift:513-520, 1100-1101` |
| Write editor | Accessibility label "Write" | `NativeLatex/App/LibreWeaveApp.swift:285` |
| Read preview | Accessibility label "Markdown preview"; "Try Again" | `NativeLatex/App/MarkdownPreview.swift:206, 313` |
| VoiceOver rotors in Write | "Images", "Tables" | `NativeLatex/MarkdownObjects/Sources/NativeLatexMarkdownObjects/MarkdownObjects.swift:500` |
| Read styling | `#2563EB` as `--link`/`--accent` in light mode; neutral link color in dark mode for contrast | `NativeLatex/App/MarkdownPreview.swift:118-122` |
| New document | "Markdown" choice in File ▸ New… | `NativeLatex/App/NewDocumentCommands.swift` |

None of these say the app only views files or only handles Markdown. Keep Read and Write as mode names: they describe what each mode does, and README and status docs already use them.

## Finding 2: where the brand does appear in Markdown code

| # | Touchpoint | Visible to users? | Persisted? | Recommendation |
| --- | --- | --- | --- | --- |
| A | `"LibreWeave couldn’t start \(pandoc.path): …"`, `NativeLatex/App/MarkdownPreview.swift:92` | Yes, in the Read error state | No | Change to brand-neutral copy such as `"Pandoc at \(pandoc.path) couldn’t start: …"`. That way no future rename has to touch it. |
| B | Attributed-string keys `LibreWeaveMarkdownHidden/Atomic/CodeBlock/Decoration/Quote`, `NativeLatex/App/MarkdownWriter.swift:8-17` | No | Not found. They exist only in in-memory text storage, and AppKit's RTF/plain-text copy drops custom attributes. | Leave as they are. |
| C | `LibreWeaveMarkdownObject/ObjectHidden/ObjectSource`, plus `writerHiddenKey = "LibreWeaveMarkdownHidden"`, `NativeLatex/MarkdownObjects/Sources/NativeLatexMarkdownObjects/MarkdownObjects.swift:6-14` | No | No | Leave as they are. **Risk:** `writerHiddenKey` copies the raw string of B's `markdownHidden` across the package boundary. If someone renames one without the other, Write silently stops hiding markup around objects and no compile error catches it. Any rename of B or C must change both in the same commit. |
| D | Older brand `libreleaf-preview-<UUID>` temp directory and `libreleaf-local` URL scheme (used in the CSP via interpolation), `NativeLatex/App/MarkdownPreview.swift:62, 149` | Not shown in the UI. The temp path could show up in Pandoc stderr. | No. The directory is removed after each render. | Rebranding doesn't require changing these. Neutral names (`markdown-preview-`, `local-asset`) are an optional cleanup. Rename the scheme in the one constant only. |
| E | `@testable import LibreWeave`, `NativeLatexTests/MarkdownWriteTests.swift:7`, `MarkdownPreviewTests.swift:5`, `NewDocumentTests.swift:4, 101` | No | No | Backend owns the module rename. These lines follow whatever it decides. |
| F | Package and module `NativeLatexMarkdownObjects`, `NativeLatex/MarkdownObjects/Package.swift` | No | No | Leave it. It was never the brand. |
| G | Markdown screenshot `landing/media/libreweave-markdown.png`, its README alt text (`README.md:23`), README "Markdown you can write and read" (`README.md:19-23`), landing caption (`landing/index.html:83`) | Yes | Published | Brag and Landing own these files. Markdown UX supplies the capture spec below. Re-shoot only after the name gate passes, because the window title and app menu show the product name. |

## Smallest complete change set

1. **Now, under any name:** neutralize string A (one line). Optionally neutralize D. Skip B, C, E and F.
2. **Only after the name gate passes:** re-capture the Markdown screenshot (G) under the final name. Capture spec: a light-mode Write window at the default width, showing a formatted heading, a paragraph and a pipe table, with the format bar and Document Mode visible. Add a matching dark-mode Read shot if Brag wants one. Capture must not bring the app forward over the owner's work (`open -g`, offscreen or window-ID capture).
3. **No Markdown-specific changes are needed for the bundle, module or display-name rename.** The window title, app menu and "Open With" entry come from Backend's `PRODUCT_NAME`/`CFBundleDisplayName`.

## Sequencing and dependencies

- Step 1 has no dependencies and can land before any name decision.
- Step 2 depends on the name review, Backend's display-name change, and Art's final icon (it appears in the screenshot's toolbar or Dock area). Brag and Landing then swap the file and alt text.
- If Backend renames the module, E changes in the same commit. Markdown UX has nothing else to coordinate.

## Validation that would prove completion

- Grep gate on `main`: `grep -rn "LibreWeave\|libreleaf" NativeLatex/App/MarkdownPreview.swift NativeLatex/App/MarkdownWriter.swift NativeLatex/MarkdownObjects/Sources` returns only the accepted internal keys B/C (plus D if it is kept). It returns no user-visible string.
- Key-pair check: B's `markdownHidden` and C's `writerHiddenKey` hold the same raw value. A one-line assert in `MarkdownWriteTests` would catch drift if a rename of B/C is ever approved.
- Existing suites still pass without opening windows over the user's work: Markdown Objects `swift test` (24), `MarkdownWriteTests`, `MarkdownPreviewTests`, `NewDocumentTests`, and `xcodebuild build-for-testing`.
- A missing or broken Pandoc path shows the new Read error text with no product name (`NativeLatexTests/MarkdownPreviewTests.swift:120` already asserts the message contains “couldn’t start”: keep that phrase or update the assert in the same commit).
- VoiceOver spot check in Write and Read: "Document Mode", "Read", "Write", "Markdown preview", and the Images/Tables rotors are announced unchanged. The app name comes only from the bundle.
- Screenshot check (step 2): the published image shows the final name and the single `#2563EB` accent, and no stale brand appears in its filename, alt text or caption.

## Migration and rollback risks

- No Markdown user data depends on the brand. Saved Markdown is plain text, the custom keys are never written to disk, and the Read temp directory is removed after each render. A rename can't corrupt `.md` files.
- Only Backend's settings migration touches Markdown preferences. Read/Write mode is per-window state (`PaneState`), not a stored default.
- Rollback for step 1 is `git revert` of a one-line change. Rollback for step 2 is restoring the previous image, alt text and caption together, because Brag or Landing own them.
- Main regression risk: renaming B without C (Finding 2, row C). Mitigation: leave both alone, or rename them together and add the assert.

## Decisions for the coordinator

1. Approve neutralizing string A now, ahead of any name decision. Recommended.
2. Keep the internal attributed keys (B/C) as they are, or rename them together with an equality assert. Recommended: keep them.
3. Clean up the stale `libreleaf` temp prefix and URL scheme (D) as a separate change, or leave them.
4. Confirm that **Read** / **Write** / **Document Mode** stay as the Markdown mode names under any brand.
5. Decide who owns re-shooting the Markdown screenshot after the name gate (Brag or Landing), using the capture spec above.
