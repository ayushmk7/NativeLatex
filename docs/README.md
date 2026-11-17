# NativeLatex planning workspace

Status: Mac-only planning and conversion validation · revised 2026-11-17. The app plan covers LaTeX, Markdown, and other readable files on Mac; no app source has been created.

## Start here

1. [Product plan](product-plan.md) — product promise, scope, decisions, success checks.
2. [Delivery plan](delivery-plan.md) — implementation order and acceptance gates.
3. [Art direction](workspaces/art/art-direction.md) — black/white light and dark, royal blue, icon, native BB-8 inspired switch.
4. [Mac UX plan](workspaces/ux/ux-plan.md) — windows, editing flows, appearance, recovery, accessibility.
5. [Mac architecture](workspaces/backend/architecture.md) — native stack, files, compilation, preview, signing.
6. [Integrations](workspaces/integrations/integrations.md) — Word, Google Docs, LibreOffice, LibreTexts, Zotero, Git.
7. [Conversion test](research/conversion-test-2026-11-17.md) — tested DOCX/ODT exports, imports, and fidelity limits.
8. [Deployment plan](deployment-plan.md) — signed Mac download on AWS; optional Vercel landing page.

## Workspace layout

The existing Herdr **NativeLatex** workspace is the primary space. Art, UX, Backend, and Integrations are the active planning workstreams. The previously linked Mobile sidebar space is [parked](workspaces/mobile/README.md) because the product is Mac only; its worktree stays accessible. Each linked space has its own Git branch and checkout; changes reach the primary branch when merged. In the app, a *workspace* will mean an ordinary local project folder in its own macOS window.

Local implementation can start without AWS or a backend. Xcode 27.2 works with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; system `xcode-select` still points to Command Line Tools because changing it requires an administrator password. TeX, Pandoc, and LibreOffice are present for local testing. Public distribution still needs a Developer ID signing identity and a valid AWS session; see the [deployment readiness checks](deployment-plan.md#current-readiness-on-this-mac).
