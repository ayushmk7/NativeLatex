# Virgule implementation brief

The owner authorized implementing the Virgule rebrand on 2026-11-18. The earlier planning-only hold no longer blocks local implementation. Virgule is still not a cleared mark; do not claim legal clearance. The coordinator owns public pushes, DNS, app installation, and cleanup.

Use `/Users/ayush/Downloads/My Projects/NativeLatex` at `main` as the code and plan source of truth. Your Herdr branch may lag behind main, but the app code is identical at the planning base. Work only in your assigned worktree and commit only your assigned changes. Do not modify another workspace's files or launch an app that steals focus. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for Xcode commands; the global developer selection is currently Command Line Tools.

The shipped name becomes **Virgule**. Keep `PRODUCT_BUNDLE_IDENTIFIER = app.libreweave.LibreWeave`, the Xcode target/scheme `LibreWeave`, Swift module `LibreWeave`, plist path, document-type declarations, and existing preference domains. Change `PRODUCT_NAME`, `CFBundleDisplayName`, and the hard-coded `TEST_HOST` together. Preserve `.libreleaf-build`, `.libreleaf-owner`, `LibreLeaf.log`, the `libreleaf-local` scheme, the `libreweave-theme` storage key, and shared Markdown style keys. These are stable internal or user-file identifiers. Keep the existing `landing/media/libreweave-*` URLs through the site cutover.

Visual constraints: one brand blue `#2563EB`, black/white light and dark modes, new slash icon with no inner box, existing BB-8 appearance switch. The app edits LaTeX, Markdown, plain text and other supported text formats. No mobile app. Avoid an outlined SF Pro wordmark; use live text or an openly licensed face. Do not add a cross-package app-name abstraction for a one-time rename.

Run meaningful checks for your changes, inspect the diff, and report the commit hash, files changed, checks, and any blockers. Do not push, deploy, install, alter DNS, rename the GitHub repository, or delete old apps; the coordinator will integrate and do that in sequence.
