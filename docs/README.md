# NativeLatex planning workspace

Status: planning only · 2026-11-16. No app source has been created.

## Start here

1. [Product plan](product-plan.md) — product promise, scope, decisions, success checks.
2. [Delivery plan](delivery-plan.md) — implementation order and acceptance gates.
3. [Art direction](workspaces/art/art-direction.md) — visual language and mockup brief.
4. [UX plan](workspaces/ux/ux-plan.md) — windows, editing flows, recovery, accessibility.
5. [Local architecture](workspaces/backend/architecture.md) — native stack, files, compilation, preview.
6. [Integrations](workspaces/integrations/integrations.md) — Word, Google Docs, LibreOffice, LibreTexts, Zotero, Git.

## Workspace layout

The existing Herdr **NativeLatex** workspace is the primary space. Art, UX, Backend and Integrations are linked Herdr worktree spaces shown beneath it in the sidebar. Each has its own Git branch and checkout, starting from the planning documents in this repository; changes made in one space reach the primary branch when merged. In the app, a *workspace* will mean an ordinary local project folder in its own macOS window.

The plan is ready for implementation without a cloud account or backend. Xcode 27.2 is installed and selected for this user's launch session through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodebuild -version` passed. The system-wide `xcode-select` path still points to Command Line Tools because changing it requires an administrator password. TeX tools are already present. See the [architecture](workspaces/backend/architecture.md) for the prerequisite check.
