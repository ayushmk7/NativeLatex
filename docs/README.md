# NativeLatex workspace

Status: Mac-only implementation in progress · revised 2026-11-17. The app plan covers LaTeX, Markdown, and other readable files on Mac.

**LibreLeaf** is the working app name (product name, bundle `app.libreleaf.LibreLeaf`, scheme `LibreLeaf`). **NativeLatex** remains the repository, Xcode project, folder, and Swift package name. Minimum macOS is **14.0** for the app and both packages.

## Start here

1. [Product plan](product-plan.md) — product promise, scope, decisions, success checks.
2. [Delivery plan](delivery-plan.md) — implementation order and acceptance gates.
3. [Art direction](workspaces/art/art-direction.md) — black/white light and dark, royal blue, icon, native BB-8 inspired switch.
4. [Mac UX plan](workspaces/ux/ux-plan.md) — windows, editing flows, appearance, recovery, accessibility.
5. [Mac architecture](workspaces/backend/architecture.md) — native stack, files, compilation, preview, signing.
6. [Integrations](workspaces/integrations/integrations.md) — Word, Google Docs, LibreOffice, LibreTexts, Zotero, Git.
7. [Conversion test](research/conversion-test-2026-11-17.md) — tested DOCX/ODT exports, imports, and fidelity limits.
8. [Deployment plan](deployment-plan.md) — planned signed Mac download on AWS; landing page live on GitHub Pages.
9. [Landing workspace plan](workspaces/landing/landing-plan.md) — page content, design, and release boundary.
10. [Adversarial workspace plan](workspaces/adversarial/review-plan.md) — parallel defect review and repair gates.
11. [Workspace prompts](prompts/README.md) — task briefs for the Claude sessions.

## Workspace layout

The existing Herdr **NativeLatex** workspace is the primary space. Art, UX, Backend, Integrations, Landing, and Adversarial are linked sidebar workspaces with their own Git worktrees. Mobile was removed because the product is Mac only. Four Claude sessions in Adversarial review functionality, security, accessibility, and build/release behavior. Changes reach the primary branch when merged. In the planned app, a *workspace* will mean an ordinary local project folder in its own macOS window; the current build opens one file per window.

## Implemented on main (checked 2026-11-17)

These are facts about integrated commit `5386b36` plus the Adversarial branch repairs `d637048` (file reload, diagnostics, build folder, output scan) and `7d52226` (BB-8 outline and focus ring), separate from the plans linked above. Test counts are the test cases in those commits.

| Area | Current state | Verified by |
| --- | --- | --- |
| App shell | `NativeLatex.xcodeproj`, scheme `LibreLeaf`, deployment target 14.0, Hardened Runtime on, ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`). SwiftUI `DocumentGroup`: **one file per window**, no folder tree, tabs, or recent-folder list. Source editing uses an AppKit `NSTextView` (`SourceTextView.swift`) with smart quotes, dashes, text replacement, autocorrect and spell check off, plus find bar and undo. | `xcodebuild -project NativeLatex.xcodeproj -scheme LibreLeaf -destination 'platform=macOS' test`: 24 test cases (BuildSafety 17, Integration 6, Appearance 1) |
| File types | Built `Info.plist` lists Finder extensions `.tex`, `.ltx`, `.latex` (`org.tug.tex`) and `.md`, `.markdown` (`net.daringfireball.markdown`) as Editor with `LSHandlerRank` `Default`; `.bib`, `.sty`, `.cls` (`org.tug.bib`/`sty`/`cls`) and other `public.plain-text` files as Editor with `Alternate`. The five `org.tug.*` and Markdown types are imported declarations; none are exported. No `public.data` claim. Installing the app adds it to Open With; the user decides whether it becomes the default app. | `plutil -extract CFBundleDocumentTypes` on the built app; `open -a LibreLeaf.app notes.md article.tex` opened both. Finder's "Change All" default not hand-tested |
| TeX build | Build (⌘B) on a `.tex`, `.ltx` or `.latex` window runs `latexmk -norc -pdf … -no-shell-escape` (or a single-pass engine fallback) into `<folder>/.libreleaf-build/<stem>-<token8>/`, where `<token8>` is the first 8 characters of this install's owner token, so a folder copied from another Mac or left after a token reset gets a fresh output folder and old outputs are never deleted. Reuse requires the full-token `.libreleaf-owner` marker, and a recursive scan refuses the build if the output tree has a symlink, hard link, special file, or unreadable folder. A failed build that latexmk won't rerun still shows file:line problems recovered from the engine `.log`. Engines tried in order: `latexmk`, then single-pass `pdflatex`/`xelatex`/`lualatex`. The folder stays next to the source on the user's disk; nothing is uploaded. PDFKit preview, build status badge, Stale marking, raw log sheet, Problems list that jumps to the line, status bar. | `BuildSafetyTests` (17) |
| External changes | Each window checks its file every 2 s and when the app becomes active. If another app changed a **clean** buffer, it reloads through NSDocument revert. If the buffer has **unsaved edits**, a "changed on disk" banner offers **Reload from Disk** or **Keep Mine**, and edits are never discarded silently. Build also refuses to save over a file that changed on disk. Folder-level FSEvents/NSFilePresenter watching is still planned. | `BuildSafetyTests` (`d637048`) |
| Markdown | Native line-based preview (headings, inline styles, code fences shown, never run). Tables, images, and math are not rendered yet. | Code review |
| Design package | `NativeLatex/Design`, linked into the app as a local Swift package. The app uses its theme (`libreLeafTheme()`), BB-8 toolbar toggle, View ▸ Appearance and Settings ▸ Appearance, `ProblemList`, `StatusBar` and `BuildStatusBadge`. `WorkspaceShell` is not used yet. | `swift test`: 7 test cases (Theme 4, BB8Render 3); `AppearanceTests` checks a white editor in Light and black in Dark. The BB-8 pill has a foreground-colored outline (1.5 pt, 2.5 pt with Increase Contrast) so it stays distinct from light and dark toolbars, and a 2 pt capsule focus ring drawn in reserved space so it is not clipped and focus doesn't shift layout |
| Integrations package | `NativeLatex/Integrations`, linked into the app. File menu: **Export Copy**, **Import Copy** (as LaTeX/Markdown), **Import LibreTexts Page**, and **Google Docs: Not Connected…**. Conversions use local Pandoc/LibreOffice and always write a new copy. Google Docs has a **fake transport only** (status `.disabled` or `.liveNotConfigured`; no OAuth client or Google API call). LibreTexts is **import only**, from licensed public pages, with attribution. | `swift test`: 17 pass, 1 live LibreTexts test skipped by default; app `IntegrationTests` (6) |
| Art | App icon (all 10 mac slots) and `AccentColor` in `NativeLatex/Assets.xcassets`. No Icon Composer `.icon` yet. | `art/tools/validate.sh`: sizes and `actool` pass |
| Landing | Live on GitHub Pages at <https://ayushmk7.github.io/NativeLatex/>, deployed by `.github/workflows/pages.yml`. Says there is no download. | Workflow run succeeded; URL returns HTTP 200 |

**Packaging (checked locally):** `xcodebuild … archive` succeeds. The archived app is ad-hoc signed with Hardened Runtime and empty entitlements, and `codesign --verify --deep --strict` passes. It is **not** Developer ID signed or notarized, and `spctl --assess` rejects it as expected. The binary is universal (`x86_64 arm64`, minos 14.0). Only the arm64 slice has been run, on this Apple silicon Mac; **the Intel slice is untested**.

**Planned, not implemented:** folder workspaces (one folder per window, file tree, tabs, recent folders), root-file selection, SyncTeX, XeLaTeX/LuaLaTeX profiles, rich Markdown (tables, images, math), live Google Docs/OneDrive sign-in, LibreTexts publishing.

**Release blockers:** Developer ID signing and AWS hosting need the owner's real Apple Developer and AWS credentials, which this workspace does not have (0 valid signing identities, no AWS session). There is no notarized build, no S3/CloudFront resource, no clean-Mac or TeX-absent test, and no Intel test. **There is no signed Mac download.**

## This Mac's toolchain

Xcode 27.2 works with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; system `xcode-select` still points to Command Line Tools because changing it requires an administrator password. TeX is **Homebrew texlive** (`latexmk`, `pdflatex`, `synctex` in `/opt/homebrew/bin`). `/Library/TeX/texbin` exists only as a broken symlink chain left from a removed MacTeX 2024 (`/usr/local/texlive` is gone), so it contains no binaries; the build service checks each candidate resolves to a real executable. Pandoc 3.13 and LibreOffice (`/opt/homebrew/bin/soffice`) are present. See the [deployment readiness checks](deployment-plan.md#current-readiness-on-this-mac).
