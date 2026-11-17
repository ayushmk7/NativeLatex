# NativeLatex Mac product plan

Status: plan, with a first implementation on main · revised 2026-11-17 · Mac only. **LibreWeave** is the working app name; NativeLatex remains the repository and project path. What is built today is listed under [Implemented on main](status.md#implemented-on-main-checked-2026-11-17); this file describes the target product.

## Product promise

LibreWeave (repository: NativeLatex) is planned as a native Mac app for opening ordinary LaTeX and Markdown files, editing them locally, and rendering a preview beside the source. LaTeX compiles with the Mac's TeX installation; Markdown renders locally. No account or network connection is required for local projects. This is a single-user product with no phone or tablet target.

The app is for authors who want a faster local editing loop than switching among a text editor, terminal, PDF viewer and Finder. It should handle a single article quickly and remain dependable on multi-file projects with images and bibliographies.

## Resolved decisions

| Question | Decision | Reason |
| --- | --- | --- |
| Native implementation | SwiftUI window and commands, AppKit source editor, PDFKit preview | Use mature macOS editing and PDF components. The current build uses an AppKit `NSTextView` editor and PDFKit; syntax color and line numbers are still planned. |
| Minimum macOS | 14.0 (app target, Design and Integrations packages) | Matches `MACOSX_DEPLOYMENT_TARGET` and package platforms. |
| Project format | Ordinary `.tex`, `.md`, `.bib`, images and related files in a folder | Keep projects portable to TeX, Git and other editors. |
| Workspace | One folder per window, several windows open at once | Separate build root, state and outputs clearly. **Planned.** The current build is a `DocumentGroup` app with one file per window and no folder tree. |
| Render target | An opened `.md` file, or an explicitly selected root `.tex` file per workspace | Render the active note by default without guessing a multi-file TeX root. |
| Build engine | Installed `latexmk`, with pdfLaTeX first and XeLaTeX/LuaLaTeX next | Let TeX tooling handle passes and bibliography work. |
| Preview | PDFKit; retain the last successful PDF with a stale label on failure | Prevent old output from looking current. |
| Local data | Source stays in the chosen folder; UI state lives in Application Support | Avoid a proprietary project database. |
| Appearance | Black/white light and dark themes with one `#2563EB` blue accent and a native BB-8 inspired switch | Follow the requested visual direction while keeping editor and PDF readable. |
| Distribution | Local Debug first; Developer ID signed and notarized ZIP for public download | Support local TeX tools and ordinary folders. |
| External formats | Non-destructive, reviewable import/export copies | The [conversion test](research/conversion-test-2026-11-17.md) found silent reference and citation changes. |

Technical detail and source references are in the [architecture](workspaces/backend/architecture.md), [art plan](workspaces/art/art-direction.md), [UX plan](workspaces/ux/ux-plan.md), and [integration plan](workspaces/integrations/integrations.md).

## First usable release: Mac

1. Open a `.tex`, `.md` or `.markdown` file directly from Finder/Open With or File > Open, or open/create a folder workspace. A direct file opens its containing folder as a workspace and selects that file. Support multiple windows, recent folders, a file tree and source tabs for text assets. Register these types as openable; the user chooses whether macOS makes NativeLatex their default app. [Apple document type registration](https://developer.apple.com/documentation/SwiftUI/DocumentGroup).
2. Provide a strong editor: undo/redo, syntax color, matching delimiters, line numbers, find/replace, comment toggle, indentation and standard macOS keyboard/menu behavior.
3. Save safely. Detect changes made by Finder, Git, cloud file providers or another editor; never silently overwrite a dirty buffer.
4. Build a selected root `.tex` file with local TeX, or Render the active Markdown file locally. The same keyboard command chooses the action from the file type. Show progress/cancel; retain TeX logs and link reliable errors to source lines.
5. Show PDF beside LaTeX or rendered Markdown beside its source. Markdown gets a native basic preview without extra tools; installed Pandoc enables richer HTML/PDF export. Retain the last successful TeX PDF on failure and mark it stale. [Apple Markdown parsing](https://developer.apple.com/documentation/foundation/attributedstring), [Pandoc formats](https://pandoc.org/MANUAL.html).
6. Export or reveal the PDF and project folder. No account is required.
7. Make the main flow work with keyboard navigation, VoiceOver, system appearance, high contrast and reduced motion.

The visual system uses white and black surfaces, one `#2563EB` blue accent from the Website base theme, and the native BB-8 inspired appearance switch described in the [art](workspaces/art/art-direction.md) and [UX](workspaces/ux/ux-plan.md) plans. Small dark-mode text uses neutral white for contrast. The switch follows the Mac's effective appearance until the user chooses an explicit Light or Dark override.

The first release should work on a real multi-file project before advanced completion or cloud exchange arrives. Its exit checks are in the [delivery plan](delivery-plan.md).

## Default file behavior

| File type | Open | Default action | Output |
| --- | --- | --- | --- |
| `.tex` | Source editor; choose root if needed | Build with `latexmk` | PDF, log and problems |
| `.md`, `.markdown` | Source editor | Render the active file locally | Markdown preview; optional Pandoc HTML/PDF export |
| `.bib`, `.sty`, `.cls`, `.txt` and other decodable text | Source editor | Save/edit; no automatic execution | Original text file |
| `.pdf` and images | Read-only viewer/asset inspector | Open/preview | Original file |

Opening a file does not execute its contents. **Build/Render** is a deliberate user action. Unknown binary formats are shown in Finder or an appropriate external app rather than interpreted as code. Additional formats can be added when their renderer and safety contract are defined; code fences inside Markdown are displayed, not executed.

## Power features after the core loop

| Stage | Capability | Dependency |
| --- | --- | --- |
| Writing speed | Outline, quick open, project search, image insertion, small templates, citation and reference completion | Reliable file model. |
| Source/PDF navigation | SyncTeX forward/reverse search, detachable preview | Stable build output and coordinate mapping. |
| Compiler choice | XeLaTeX/LuaLaTeX profiles; optional Build on Save | Tool discovery, cancellation and conflict handling. |
| Interchange | DOCX and ODT reviewable exports first; import copies only after a conversion report is proven | Fidelity corpus and review in Word/Writer. |
| Connected exchange | Opt-in owner-only Google Docs and OneDrive transfer; then evaluate LibreTexts publishing | OAuth, content ownership, conflict and license handling. |

The first release excludes a collaboration server, bundled TeX distribution, package manager, WYSIWYG editor, arbitrary execution recipes and proprietary file format. There is no iPhone or iPad app track.

## Critical behavior

- **No silent data loss:** compare with the disk version before saving; stop and offer recovery if another process edited it. Imports and exports create copies.
- **No false build success:** only publish a PDF from the latest successful build for that root. Label older output after a failed or canceled build.
- **No surprise execution or upload:** never compile on opening a folder, enable shell escape by default or contact a service during ordinary editing/building. Special project recipes require explicit trust.
- **No cross-workspace bleed:** each window owns its root, build generation, errors, preview and editing state.
- **Graceful missing tools:** editing works without TeX or Pandoc; explain a missing dependency only when its action is requested.

## Integration posture

“Docs” means Google Docs here; “libretext” is treated as LibreTexts, with LibreOffice Writer covered too because the term could refer to it. Word and Writer exchange use reviewable DOCX/ODT copies. Google Docs begins with manual exchange and can gain a narrow, opt-in Drive connector for the owner's account. LibreTexts begins as a reviewed publishing handoff until its supported API and author workflow are verified. See the [integration evidence and limits](workspaces/integrations/integrations.md) and [conversion test](research/conversion-test-2026-11-17.md).

AWS is planned to serve a signed Mac download once one exists. The landing page is live on GitHub Pages at <https://libreweave.ayushmadhav.com/> with no download. The app itself runs locally and needs no website or server. The [deployment plan](deployment-plan.md) records signing, artifact hosting, account prerequisites, and release checks.

## Product success checks

1. A person opens a `.tex` file from Finder, edits it, builds it and sees the PDF without opening Terminal.
2. A person opens a `.md` file from Finder, edits it and sees a local rendered preview without installing TeX or Pandoc.
3. Two workspace windows build distinct roots concurrently without mixing files, errors or output.
4. A multi-file paper with an image and bibliography builds; clicking a reported error opens the correct file and line.
5. If an external editor changes an open file, NativeLatex never silently replaces that edit.
6. If a build fails, the PDF remains available and is unmistakably marked as previous output.
7. With TeX absent, a user can still edit and save, and Build gives actionable setup guidance.
8. These flows can be completed by keyboard; essential state and errors are announced to VoiceOver.
9. Every shipped import/export format has a conversion report and leaves the original untouched.

## Limits to validate during implementation

- Custom `.latexmkrc`, shell escape, `minted` and unusual encodings need fixtures before a trusted-project mode ships.
- DOCX/ODT fidelity varies by document. Ship only cases backed by the conversion corpus; disclose unsupported content.
- A direct LibreTexts publisher depends on a supported API and permissions model from that platform.
