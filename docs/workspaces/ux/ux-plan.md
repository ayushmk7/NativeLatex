# NativeLatex Mac UX plan

Status: plan · revised 2026-11-17 · Mac only. The `NativeLatex/Design` package (theme, BB-8 toggle with outlined pill and unclipped capsule focus ring, `WorkspaceShell`; 7 test cases) is linked into the LibreWeave app. The app uses its theme, BB-8 toggle, appearance menu and settings, problems list and status bar; `WorkspaceShell` is not used yet. The app currently opens one file per window. Implemented from this plan: under 760 pt the window shows source or preview at full width with a labeled Preview toggle (⌥⌘P); the disk-conflict banner spans the pane; stale output is shown once, by the toolbar badge; the Markdown preview states its limits and underlines links in brand blue.

## Product promise

Open LaTeX or Markdown files directly, write in ordinary folders on the Mac, and inspect the rendered output beside the source. LaTeX uses a local TeX installation; Markdown has a local preview. A workspace is a folder; a LaTeX project is a root `.tex` file and the files it includes. The app can have several workspace windows open at once. Source files remain usable from Finder, Git, and other editors.

This follows the macOS expectation that documents are accessible from Finder and through standard File menu commands, while making room for multiple windows and keyboard use. [Apple file management](https://developer.apple.com/design/human-interface-guidelines/file-management), [Apple macOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).

## Core mental model

| Object | What the user sees | Rule |
| --- | --- | --- |
| Workspace | A named folder/window with a file tree, open tabs, editor, and preview | Each open workspace has its own window and selected build root. Opening an already open folder focuses its window. |
| Project | A root `.tex` file inside a workspace | The user chooses it explicitly when the folder has more than one plausible root. Its name appears beside Build. |
| Document | A `.tex`, `.md`, `.bib`, or other decodable text file | Files are edited in place and saved with macOS document conventions. Unsaved changes are shown clearly. |
| Build/Render | A local compile of the selected TeX root, or preview of the active Markdown file | The result belongs to that workspace and target. A failed TeX build retains the last successful PDF, clearly labeled as stale. |

The app should remember recent workspaces and each workspace's selected root and pane layout. A workspace does not require a proprietary project file. Any app-specific metadata should live in app settings unless a future feature genuinely needs to travel with the folder.

## Window structure

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Folder / target title       Build/Render status   Preview   BB-8 switch │
├──────────────┬────────────────────────────┬────────────────────────────────┤
│ Files        │ Tabs: main.tex  notes.md    │ PDF or Markdown preview        │
│ + outline    │                            │ page / zoom / search           │
│              │ Source editor              │                                │
│              │                            │                                │
├──────────────┴────────────────────────────┴────────────────────────────────┤
│ Problems: 2 errors, 3 warnings  |  line, column  |  build duration       │
└────────────────────────────────────────────────────────────────────────────┘
```

- Leading sidebar: workspace files, followed by a collapsible outline for the active `.tex` document. Keep file hierarchy readable; hide the sidebar on small windows or by command. Apple recommends a hideable sidebar and standard View menu commands. [Apple sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars).
- Center: source tabs, monospaced editor, line numbers, search, and an obvious active cursor. Split the editor only if users later need simultaneous source files; the PDF split solves the first need.
- Trailing pane: PDF preview for LaTeX or rendered Markdown for `.md`; detachable into a second window for two-display work. PDF has fit width/page, zoom, page navigation, and find.
- Bottom panel: Problems by default after a failed build; a Log tab exposes full output. Its height is resizable and it can be closed without losing errors. The toolbar stays sparse: sidebar, root title, Build, build state, preview, and the BB-8 appearance control. [Apple toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Apple split views](https://developer.apple.com/design/human-interface-guidelines/split-views).
- A narrow window prioritizes the editor. Preview becomes a toggle, not a compressed second column; problems become a drawer/panel.

## Appearance and BB-8 control

The interface has two visual appearances: paper-white with black text, and near-black with white text. Electric blue from the Website homepage (`#0F2BFF` light, `#2438FF` dark fill, `#7A93FF` as text on black) is the only brand accent, used for selection, focus, active controls, and key actions. Problems still need text, symbols, and system semantic status treatment so color alone never conveys an error. The editor and Markdown preview follow the selected appearance; the generated PDF keeps its actual page colors, usually white, so a dark UI does not misrepresent the document.

The app starts in **Use System**. In **NativeLatex > Settings > Appearance**, offer **Use System**, **Light**, and **Dark**. Use System tracks macOS changes while the app is open. The selected appearance is one app-wide preference, so all workspace windows, sheets, menus, editor, and preview chrome change together. The BB-8 switch in the trailing toolbar displays the *effective* light/dark appearance; clicking it chooses the opposite appearance as an explicit app override. **Use System** in Settings or **View > Appearance** restores automatic behavior. If macOS changes while Use System is selected, the switch updates without modifying the preference. This is a deliberate, limited override of Apple's recommendation to follow the system appearance because the user requested a visible switch. [Apple Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Apple appearance behavior](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance).

Adapt the day/night BB-8 artwork from `/Users/ayush/Downloads/Website/src/components/v2/BB8Toggle.astro` and `/Users/ayush/Downloads/Website/src/components/pro/opt4/bb8.css` as a native Mac control; the Downloads design guide at `/Users/ayush/Downloads/distinctive-frontend.md` informs its distinctive character. Keep the robot silhouette and day/night direction recognizable, with a restrained short movement confined to the switch. Do not carry over browser `localStorage`, hidden-checkbox behavior, web fonts, or full-page entrance animation. The app must be immediately usable while the switch animates. With Reduce Motion, change the scene and thumb position immediately without rolling, bounce, or scenery movement. [Apple motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion).

The switch needs a visible focus ring and a comfortably sized hit area. Tab reaches it; Space activates it. VoiceOver announces **Dark appearance, on/off** and a hint that **Use System** is in Settings. The current appearance must remain evident without interpreting the BB-8 art: the View menu has checked System/Light/Dark options, and the control's help text says **Switch to Light Appearance** or **Switch to Dark Appearance**. The control reflects the current state even when another workspace window changes it. Test both appearances with Increase Contrast, system accent overrides, and PDF pages of varied colors. [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Apple color](https://developer.apple.com/design/human-interface-guidelines/color).

## Primary journeys

### First launch and first PDF

1. Start screen offers **Open File**, **Open Folder**, **New Workspace**, and recent workspaces. It follows macOS appearance immediately; there is no account, theme, or TeX setup wizard. Opening `.tex`, `.md`, or `.markdown` from Finder/Open With opens its containing folder as a workspace and selects the file. The app registers these types without changing the user's default app choice. [Apple document type registration](https://developer.apple.com/documentation/SwiftUI/DocumentGroup).
2. New Workspace asks for a folder location, name, and a blank LaTeX article or Markdown note. Confirming creates ordinary files and opens the new workspace window; canceling creates nothing. Opening an existing file edits it in place, without copying it into app storage.
3. On first Build, check for a usable local TeX engine. If missing, show the detected state and a path to install/configure one; keep the draft editable. Never silently install a multi-gigabyte toolchain.
4. Build saves current source files, shows progress, then opens the PDF. Errors appear with file, line, severity, and a concise message. A click opens the source and selects the line.
5. Closing and reopening the app restores recent folders and per-window context, subject to the user's macOS window restoration setting.

Success criterion: a user with TeX installed can create an article, change its title, compile, and see the new PDF without leaving the app.

### Open and render Markdown

1. Open a `.md` or `.markdown` file directly or select one in a workspace. The active file becomes the render target; no TeX root selection is needed.
2. **Render** creates a local basic Markdown preview even without TeX or Pandoc. Show links, headings, lists, emphasis, and code fences as content; never execute code fences. For images, tables, math, or raw HTML that the basic renderer cannot display, show a visible limitation and offer the richer Pandoc route when installed.
3. When Pandoc is installed, **Export** can produce an HTML or PDF copy with a conversion log. Missing Pandoc affects export, not basic editing and preview.
4. Switching between a `.tex` and `.md` tab switches the action label between Build and Render and shows the matching preview. If an older preview is shown after a failed render, label it stale.

Success criterion: a user can double-click a Markdown file, edit it, press ⌘B, and see an updated local preview without another installation.

### Existing multi-file project

1. **Open Folder** uses a standard folder picker. Show the actual tree, including `.tex`, `.md`, `.bib`, images, and included files; filter noisy build artifacts from the tree by default, with a reveal option.
2. If one obvious root is found, suggest it. If ambiguous, ask the user to choose from `.tex` files; do not guess and compile the wrong paper.
3. Opening another folder makes another workspace window. The Window menu switches between them. Each window keeps its own root, tabs, PDF, problems, and layout.
4. Renaming or moving a source file in the sidebar updates the tree and open tab. The app warns when the selected root or an open file is removed externally. It never silently overwrites external edits.

Success criterion: two projects in separate folders can be edited and built independently, with no output or error list crossing windows.

### Edit, compile, diagnose

1. Source editor supports syntax color, matching braces, indentation, comment toggle, find/replace, and filename completion. The first version can use straightforward completion; language-server features are a later enhancement.
2. **Build** is explicit and keyboard accessible. A visible progress state prevents accidental duplicate runs. Cancel stops the current build and leaves source intact.
3. Problems sort by severity and source position. Every item links to a file and line when the compiler provides them; unparsed output remains in Log. Warnings are visible without taking over the screen.
4. On success, the PDF refreshes at approximately the same page and zoom; on failure, the prior PDF remains visible with a **Previous successful build** label and timestamp. No stale preview may look current.
5. Source-to-PDF and PDF-to-source jumps should use SyncTeX when available. If mapping is missing, retain ordinary page navigation and explain why the jump is unavailable. This is a valuable second milestone, not a reason to delay a reliable compile loop.

Success criterion: a broken `\\ref` or missing package is diagnosable from a click on a problem row, and the last successful output is never mistaken for the new build.

### Files, figures, citations, and templates

- Dragging an image into a workspace copies it into a user-chosen folder (default `figures/`) and inserts a relative `\\includegraphics` path. Ask before replacing an existing file. Plain drag into the editor may insert a relative path without moving the file.
- `.bib` is edited as text in the first release. Citation completion can index keys from workspace `.bib` files later; never mutate a bibliography entry to perform a lookup.
- New document templates are tiny, readable `.tex` or `.md` files. Start with a blank article, report and Markdown note; the picker can grow only after demand. Project files remain plain source files.
- Export the generated PDF through a standard Save/Share flow. Source remains available as the workspace folder; a **Reveal in Finder** action locates either source or PDF.

## Interchange and integrations

The first release should make the local files easy to exchange: open or reveal a `.tex` folder, import ordinary assets, export PDF, and use macOS Share where appropriate. A user can save the folder in a provider-synced location of their choice; the app should respond safely to external changes. This delivers useful interoperability without making a cloud account part of the editing loop.

For Word, Google Docs, and the likely intended **LibreTexts** platform, the UI should present conversions as **Import a copy** or **Export a copy** and preview conversion results before replacing source. LaTeX, DOCX, Google Docs, and web pages do not represent every equation, macro, citation, or layout the same way. The app must disclose unsupported content and keep the original intact. Do not label a one-way conversion “sync.”

| Target | User-facing flow to evaluate | Required proof before shipping |
| --- | --- | --- |
| Word | Import DOCX as a new workspace; export a copy as DOCX | Compare equations, tables, images, citations, section structure, and tracked changes behavior on real documents. |
| Google Docs | Start with file import/export through DOCX or PDF; investigate account-backed export later | OAuth scope review, offline behavior, and a non-destructive round trip test. |
| LibreTexts | Import permitted pages or export content in a format LibreTexts accepts | Verify platform API, authentication, license/attribution, math rendering, and image handling. |

Do not place provider-specific buttons in the main toolbar before any integration meets those proofs. Put them under File > Import/Export or Share, where occasional document transfer belongs.

## Commands and accessibility

| Action | Shortcut | Where | Status |
| --- | --- | --- | --- |
| New document (chooser: LaTeX, Markdown, Plain Text) | ⌘N | File ▸ New… | Shipped |
| Open another document (same Open panel as File ▸ Open…) | ⌘⇧N | File ▸ Open Another Document… | Shipped |
| Open file | ⌘O | File ▸ Open… (native, type-filtered) | Shipped |
| Save active file | ⌘S | File | Shipped (native) |
| Build TeX | ⌘B | Toolbar Build button (LaTeX windows; untitled ones save first) | Shipped |
| Cancel build | ⌘. | Toolbar Cancel button while building | Shipped |
| Markdown preview | none | Updates live while typing | Shipped |
| Show/hide preview | ⌥⌘P | Toolbar Preview toggle | Shipped |
| Find in active file | ⌘F | Edit ▸ Find (native find bar) | Shipped |
| Open folder | proposed | File | Proposed (no folder workspace yet) |
| Quick open file | ⌘⇧O | File | Proposed |
| Show/hide sidebar | ⌘⌥S | View | Proposed (no sidebar yet) |
| Jump to next problem | F8 | Build | Proposed |

Proposed shortcuts still need checking against macOS and editor conflicts; every action also needs a menu or accessible control. Appearance commands need no dedicated shortcut because the BB-8 control is keyboard reachable and View > Appearance is available. Expose file tree, tabs, editor, PDF controls, appearance switch, and problem rows in a predictable keyboard focus order. Announce build completion and errors through accessibility status without shifting focus from the editor. Use text and symbols alongside severity colors. Respect system appearance when Use System is chosen, reduced motion, increased contrast, and text scaling. Apple calls for keyboard access and audits of accessibility, including adequate macOS control size and contrast. [Apple macOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Build states and recovery

| State | Visible response | Safe next action |
| --- | --- | --- |
| No TeX engine | Local toolchain needed; show detected paths and setup link | Configure path, retry; editing continues |
| Build running | Spinner/progress, root name, Cancel | Cancel or wait; never launch a second build for that root |
| Build failed | Error count, problem list, stale PDF badge | Jump to error, edit, rebuild |
| External file change | Filename and conflict notice if local edits exist | Compare or choose which content to keep; do not overwrite silently |
| Missing root/file | Clear missing path and root chooser | Select another root or locate moved file |
| Import/conversion loss | Summary of unsupported items before final save | Inspect result, keep or discard imported copy |

## Delivery sequence

| Milestone | User-visible scope | Exit check |
| --- | --- | --- |
| 1. Reliable local loop | Multi-workspace windows; direct `.tex`/`.md` open; source editing; explicit TeX root; local compile; PDF and Markdown previews; linked errors; standard save/open/recent; PDF export; both appearances and BB-8 control | Two independent workspaces compile correctly; Markdown renders without TeX; failed build marks previous PDF stale; external edits do not get silently overwritten; appearance follows macOS until overridden and updates every window. |
| 2. Writing speed | Outline, templates, image insertion, project search, citation key completion, SyncTeX jumps, preview detach | Real multi-file paper remains responsive and jumps resolve to the right source. |
| 3. Interchange | Proven DOCX import/export; Google Docs and LibreTexts paths only after capability and loss audits | No source replacement, clear conversion report, and documented unsupported cases. |

Live collaboration, simultaneous cloud editing, and a built-in package manager are outside the initial product. Their complexity and data ownership requirements would distract from the local compile loop. Revisit them only after the editor is reliable on real projects.

## UX validation before build

Prototype and observe four Mac tasks: create a first article, open a multi-file thesis and select root, fix a compile error, and switch between two workspace windows. Test a keyboard-only path and a VoiceOver path for the same tasks. Switch macOS appearance while Use System is selected, toggle BB-8 in one of two windows, restore Use System, and repeat with Reduce Motion and Increase Contrast enabled. These should expose wrong-root assumptions, hidden build state, focus traps, stale PDF confusion, and appearance state that differs between windows before implementation hardens them.
