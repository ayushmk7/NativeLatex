# NativeLatex product plan

Status: planning only · 2026-11-16

## Product promise

NativeLatex is a native macOS app for writing LaTeX in ordinary folders, compiling with the Mac's TeX installation, and reviewing the PDF and errors beside the source. It works without an account or network connection. Each folder opens as its own workspace window, so several papers or books can be open and compiled independently.

The app is for authors who want a faster local editing loop than switching among a text editor, terminal, PDF viewer and Finder. It should handle a single article quickly and remain dependable on multi-file projects with images and bibliographies.

## Resolved decisions

| Question | Decision | Reason |
| --- | --- | --- |
| Native implementation | SwiftUI window and commands, AppKit source editor, PDFKit preview | Use mature macOS editing and PDF components. |
| Project format | Ordinary `.tex`, `.bib`, images and related files in a folder | Keep projects portable to TeX, Git and other editors. |
| Workspace | One folder per window, several windows open at once | Separate build root, state and outputs clearly. |
| Build root | Explicitly selected `.tex` file per workspace | Avoid compiling the wrong document in a multi-file folder. |
| Build engine | Installed `latexmk`, with pdfLaTeX first and XeLaTeX/LuaLaTeX next | Let TeX tooling handle passes and bibliography work. |
| Preview | PDFKit; retain the last successful PDF with a stale label on failure | Prevent old output from looking current. |
| Local data | Source stays in the chosen folder; UI state lives in Application Support | Avoid a proprietary project database. |
| Distribution | Developer ID signed/notarized local app first | Support the local TeX toolchain and ordinary folders. |
| External formats | Non-destructive import/export copies | Document models do not convert losslessly. |

Technical detail and source references are in the [architecture](workspaces/backend/architecture.md) and [integration plan](workspaces/integrations/integrations.md).

## First usable release

1. Open or create a folder workspace. Support multiple windows and recent folders. Show a file tree and source tabs for `.tex`, `.bib`, `.sty`, `.cls` and other text assets.
2. Provide a strong editor: undo/redo, syntax color, matching delimiters, line numbers, find/replace, comment toggle, indentation and standard macOS keyboard/menu behavior.
3. Save safely. Detect changes made by Finder, Git, cloud file providers or another editor; never silently overwrite a dirty buffer.
4. Choose a root `.tex` file and Build explicitly. Detect local TeX, show progress/cancel, retain the full log and link reliable errors to source lines.
5. Show the PDF beside source with zoom, page navigation and search. Retain the last successful PDF on failure and mark it stale.
6. Export or reveal the PDF and project folder. No account is required.
7. Make the main flow work with keyboard navigation, VoiceOver, system appearance, high contrast and reduced motion.

The first release should work on a real multi-file project before advanced completion or cloud exchange arrives. Its exit checks are in the [delivery plan](delivery-plan.md).

## Power features after the core loop

| Stage | Capability | Dependency |
| --- | --- | --- |
| Writing speed | Outline, quick open, project search, image insertion, small templates, citation and reference completion | Reliable file model. |
| Source/PDF navigation | SyncTeX forward/reverse search, detachable preview | Stable build output and coordinate mapping. |
| Compiler choice | XeLaTeX/LuaLaTeX profiles; optional Build on Save | Tool discovery, cancellation and conflict handling. |
| Interchange | DOCX and ODT import/export copies with a conversion report | Fidelity corpus and review in Word/Writer. |
| Connected exchange | Opt-in Google Docs transfer, then evaluated LibreTexts publishing path | OAuth, content ownership, conflict and license handling. |

The scope excludes a collaboration server, bundled TeX distribution, package manager, WYSIWYG editor, arbitrary execution recipes and proprietary file format. These do not improve the first local editing loop enough to justify their cost.

## Critical behavior

- **No silent data loss:** compare with the disk version before saving; stop and offer recovery if another process edited it. Imports and exports create copies.
- **No false build success:** only publish a PDF from the latest successful build for that root. Label older output after a failed or canceled build.
- **No surprise execution or upload:** never compile on opening a folder, enable shell escape by default or contact a service during ordinary editing/building. Special project recipes require explicit trust.
- **No cross-workspace bleed:** each window owns its root, build generation, errors, preview and editing state.
- **Graceful missing tools:** editing works without TeX or Pandoc; explain a missing dependency only when its action is requested.

## Integration posture

“Docs” means Google Docs here; “libretext” is treated as LibreTexts, with LibreOffice Writer covered too because the term could refer to it. Word and Writer exchange use DOCX/ODT copies. Google Docs begins with manual exchange and can gain a narrow, opt-in Drive connector. LibreTexts begins as a reviewed publishing handoff until its supported API and author workflow are verified. See the [integration evidence and limits](workspaces/integrations/integrations.md).

## Product success checks

1. A person with TeX installed creates a folder, edits an article, builds it and sees the PDF without opening Terminal.
2. Two workspace windows build distinct roots concurrently without mixing files, errors or output.
3. A multi-file paper with an image and bibliography builds; clicking a reported error opens the correct file and line.
4. If an external editor changes an open file, NativeLatex never silently replaces that edit.
5. If a build fails, the PDF remains available and is unmistakably marked as previous output.
6. With TeX absent, a user can still edit and save, and Build gives actionable setup guidance.
7. These flows can be completed by keyboard; essential state and errors are announced to VoiceOver.
8. Every shipped import/export format has a conversion report and leaves the original untouched.

## Limits to validate during implementation

- Custom `.latexmkrc`, shell escape, `minted` and unusual encodings need fixtures before a trusted-project mode ships.
- DOCX/ODT fidelity varies by document. Ship only cases backed by the conversion corpus; disclose unsupported content.
- A direct LibreTexts publisher depends on a supported API and permissions model from that platform.
