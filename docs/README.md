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

These are facts about merged code, separate from the plans linked above.

| Area | Current state | Verified by |
| --- | --- | --- |
| App shell | `NativeLatex.xcodeproj`, scheme `LibreLeaf`, deployment target 14.0, Hardened Runtime on, ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`). SwiftUI `DocumentGroup`: **one file per window**, SwiftUI `TextEditor`, no folder tree, tabs, or recent-folder list. | `xcodebuild … -scheme LibreLeaf test`: 5 `BuildSafetyTests` pass |
| File types | `LibreLeaf-Info.plist` declares `org.tug.tex` (`tex`, `ltx`, `latex`) and `net.daringfireball.markdown` (`md`, `markdown`) as Editor with `LSHandlerRank` `Default`, plus `public.plain-text` and `public.data` as `Alternate`. The user still chooses the default app in Finder. | Plist review; Finder Open With not yet hand-tested |
| TeX build | Build (⌘B) on a `.tex` window runs `latexmk -norc -pdf … -no-shell-escape` (or a single-pass engine fallback) into `<folder>/.libreleaf-build/<stem>/`, guarded by an owner token and symlink checks. PDFKit preview, Stale badge, raw log sheet, file:line diagnostics. | `BuildSafetyTests`: unsafe root names, output-folder guards, diagnostics, cancel, newer build supersedes older and produces a PDF. Preview UI not hand-tested. |
| Markdown | Native line-based preview (headings, inline styles, code fences shown, never run). Tables, images, and math are not rendered yet. | Code review |
| Design package | `NativeLatex/Design`: theme tokens, BB-8 appearance toggle, `WorkspaceShell`. Not yet wired into the app target. | `swift test`: 4/4 pass |
| Integrations package | `NativeLatex/Integrations`: local Pandoc/LibreOffice conversions, Google Docs behind a transport protocol with **fake transport only** (status `.disabled` or `.liveNotConfigured`), LibreTexts import of licensed public pages. Not yet wired into the app target. | `swift test`: 17 pass, 1 live LibreTexts test skipped by default |
| Art | App icon (all 10 mac slots) and `AccentColor` in `NativeLatex/Assets.xcassets`. No Icon Composer `.icon` yet. | `art/tools/validate.sh`: sizes and `actool` pass |
| Landing | Live on GitHub Pages at <https://ayushmk7.github.io/NativeLatex/>, deployed by `.github/workflows/pages.yml`. Says there is no download. | Workflow run succeeded; URL returns HTTP 200 |

**Planned, not implemented:** folder workspaces (one folder per window, file tree, tabs, recent folders), root-file selection, SyncTeX, XeLaTeX/LuaLaTeX profiles, conversion UI in the app, live Google Docs/OneDrive sign-in, LibreTexts publishing.

**Release blockers:** no Developer ID identity in the keychain (0 valid identities), no notarized build, no AWS session or S3/CloudFront resources, no clean-Mac or TeX-absent test. **There is no signed Mac download.**

## This Mac's toolchain

Xcode 27.2 works with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; system `xcode-select` still points to Command Line Tools because changing it requires an administrator password. TeX is **Homebrew texlive** (`latexmk`, `pdflatex`, `synctex` in `/opt/homebrew/bin`). `/Library/TeX/texbin` exists only as a broken symlink chain left from a removed MacTeX 2024 (`/usr/local/texlive` is gone), so it contains no binaries; the build service checks each candidate resolves to a real executable. Pandoc 3.13 and LibreOffice (`/opt/homebrew/bin/soffice`) are present. See the [deployment readiness checks](deployment-plan.md#current-readiness-on-this-mac).
