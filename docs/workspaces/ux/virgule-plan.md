# Virgule candidate: UX plan

**Status:** planning only. Virgule is a candidate name. Nothing here renames code, assets, bundle IDs, installed apps, URLs, or releases, and nothing is published. Written against `main` at `840319f`. The `ux` branch this file is committed on is behind `main`; paths and line numbers below refer to `main`.

Scope: window, menu, settings, and file-open copy; onboarding and accessibility; appearance; default file handler continuity; what users see during migration. Bundle ID, build settings, signing, and the build-output folder are Backend's. Markdown Read/Write wording is Markdown UX's. Icon and wordmark belong to Art.

## Name gate (applies to everything below)

- **Public-rename hold.** There is already an iPhone/iPad news app called Virgule (App Store ID 1245101112), and a preliminary search turned up a Canadian VIRGULE trademark listing that mentions software. This plan does not claim the name is clear, and it does not claim that listing applies to us. No user-facing build, release note, screenshot, or site copy says "Virgule" until a proper name review approves it.
- **Reversible internal prototype.** This is the only Virgule work allowed before approval. See "Prototype path" below.
- **Fallback if Virgule is rejected.** Keep LibreWeave and change nothing user-facing. The one durable UX change in this plan, a single app-name source (step 1), is worth having under any name. A later candidate would reuse the same change set and only swap the value.

## Current touchpoints (existing behavior)

The app is currently called **LibreWeave**. The bundle ID is `app.libreweave.LibreWeave`. Repo, project, and package names stay `NativeLatex` (`docs/status.md:5`). There was one earlier rename, LibreLeaf → LibreWeave, and its migration code is the model for this one.

**Names macOS derives from the bundle (no app code involved):**
- The app menu items (About, Hide, Quit), the Settings window, the Dock, Finder, Open With, and the VoiceOver app name come from `PRODUCT_NAME` / `INFOPLIST_KEY_CFBundleDisplayName = LibreWeave` (`NativeLatex.xcodeproj/project.pbxproj:192,199,213,220`).
- There is no custom About panel, Help book, onboarding screen, or welcome window. On launch, `DocumentGroup` shows the system Open panel (`NativeLatex/App/LibreWeaveApp.swift:24`).
- Window titles are file names from `DocumentGroup` and never contain the app name.

**Hard-coded app name in user-facing strings:**
- `NativeLatex/App/BuildService.swift:31` (unowned output folder) and `:33` (unsafe folder path)
- `NativeLatex/App/Conversions.swift:19` (unsaved file) and `:103` (Import panel message)
- `NativeLatex/App/LibreWeaveApp.swift:334` (reload failed)
- `NativeLatex/App/MarkdownPreview.swift:92` (Pandoc launch failed)
- `NativeLatex/App/TextDocument.swift:16` (not UTF-8)
- `NativeLatex/Integrations/Sources/NativeLatexIntegrations/Conversion.swift:54,56,60` (missing tool, cannot convert, will not overwrite)
- `NativeLatex/Integrations/Sources/NativeLatexIntegrations/GoogleDocs.swift:31,33`
- `NativeLatex/Integrations/Sources/NativeLatexIntegrations/LibreTexts.swift:28,30`
- `NativeLatex/Integrations/Sources/NativeLatexIntegrations/Process.swift:42`
- Design demo: `NativeLatex/Design/Sources/NativeLatexDesignDemo/DemoApp.swift:12,38,68,88`. This is sample content, not the shipped app.

**Tests that check the name in copy:** `NativeLatexTests/IntegrationTests.swift:29`, `NativeLatex/Integrations/Tests/NativeLatexIntegrationsTests/ConversionTests.swift:139`, `ProviderTests.swift:38`.

**Settings and appearance:**
- `Settings { AppearanceSettingsView() }` (`LibreWeaveApp.swift:34`) contains one "Appearance" picker: Use System / Light / Dark (`NativeLatex/Design/Sources/NativeLatexDesign/AppearanceStore.swift:13-15,66`). The choice is stored under the `appearanceMode` key in the app's preferences domain (`AppearanceStore.swift:26`).
- The BB-8 toggle's label, value, and hint don't mention the app (`NativeLatex/Design/Sources/NativeLatexDesign/BB8Toggle.swift:33-36`). The stale doc comment "NativeLatex > Settings" (`AppearanceStore.swift:58`) is a comment only.
- Appearance migration: on first launch the app copies `appearanceMode` from `app.libreleaf.LibreLeaf`, read-only, and only if the current domain has no value and the old value is valid (`LibreWeaveApp.swift:10-21`). `AppearanceTests.testAppearanceChoiceMigratesFromLibreLeafDomain` covers it.

**File handling:**
- `LibreWeave-Info.plist` declares `.tex/.ltx/.latex` and `.md/.markdown` as Editor/Default, and `.bib/.sty/.cls` plus `public.plain-text` as Editor/Alternate. The type names are format names ("LaTeX Document", "Markdown Document", "Plain Text") and contain no brand. The app never claims `public.data` (`NativeLatex/App/TextDocument.swift:24`).
- New… offers LaTeX, Markdown, and Plain Text (`NativeLatex/App/NewDocumentCommands.swift:19-21,64-67`). The copy describes an editor for several formats, so it already meets the "not view-only, not one format" rule.

**Internal identifiers users never see (leave unchanged):** the `LibreWeaveMarkdown*` attributed-string keys (`MarkdownWriter.swift:8-17`, `MarkdownObjects.swift:6-14`), the `nativelatex-*` temp folder prefixes, the `LIBREWEAVE_SNAPSHOT_DIR` / `NATIVELATEX_LIVE_NETWORK` test environment variables, and the `.libreleaf-build` / `.libreleaf-owner` / `LibreLeaf.log` build-output names (Backend owns these; `BuildService.swift:41,57,124,153`).

**State tied to the bundle ID.** A bundle ID change resets each of these for the user:
- preferences: the appearance choice and the build owner token
- Open Recent
- saved window state
- LaunchServices default-app choices made with Finder's "Change All"
- the app's TCC/Files & Folders grants, if any

## Smallest complete change set

Only steps 1–2 are safe to land before the name review. Steps 3–6 wait for approval.

1. **One app-name source (lands under any name).** Add one `appName` value read from `Bundle.main` `CFBundleDisplayName`, falling back to `CFBundleName`. Replace the ~16 hard-coded "LibreWeave" strings listed above with it. Copy in the Integrations package can't see the app bundle there, so pass the name in or use `Bundle.main` at the call site; don't add a second hard-coded name. Change the three copy tests to assert on the same value instead of the literal. No visible change ships with this step.
2. **Copy check.** Reread each string with a placeholder name. Each must stay correct with any name, with no grammar tied to "Libre…". None should imply a viewer or a single format. All of today's strings pass this check.
3. **Display name (after approval; Backend change, UX validates).** Set `CFBundleDisplayName` / `PRODUCT_NAME` to the approved name. The macOS app menu, About, Hide, Quit, Settings window title, Dock, Finder, Open With, and the VoiceOver app name all follow from that with no app code. Nothing else in UX needs a code edit.
4. **Preferences carry-over, only if the bundle ID changes.** Extend `migrateAppearance` to read the current `app.libreweave.LibreWeave` domain first, then `app.libreleaf.LibreLeaf`, keeping the same rules: read-only, existing value wins, invalid values ignored. The owner token needs the same chain on the Backend side. If the bundle ID stays the same, skip this step entirely.
5. **Default-handler continuity, no new UI.** Keep every `CFBundleDocumentTypes` entry, rank, and UTI byte-for-byte. Don't call `NSWorkspace.setDefaultApplication` or any other API that takes over defaults; the user picks the default app. If the bundle ID changes, the release note says: "If .tex or .md files open in another app, choose one in Finder → Get Info → Open with → Change All." Open Recent starts empty after a bundle ID change; the release note says that too. There is no public API to import another app's recents, so we don't attempt it.
6. **Leftover copy.** Fix the `AppearanceStore.swift:58` comment, and move the Design demo strings to the approved name or to a neutral "Sample". The README and screenshots belong to Brag.

Deliberately left out: an onboarding or "What's new" window (nothing like it exists, and steps 3–5 don't need one), an in-app rename notice, any change to BB-8, accent, or appearance behavior, and any rename of internal keys or folders.

## Prototype path (reversible, before approval)

- Land step 1 on `ux`. The shipped name stays LibreWeave.
- Build a local Debug copy with `PRODUCT_NAME`/`CFBundleDisplayName` overridden on the `xcodebuild` command line only. Keep the **same bundle ID**, so nothing new registers with LaunchServices and file defaults don't move. Put the output in a temporary DerivedData path. Never copy it into `dist/` or `/Applications`.
- Use it to check how the name reads in the menus, Settings, Open With, and VoiceOver. To roll back, delete the build. No source contains "Virgule", and that stays true.
- Don't build a prototype with a *different* bundle ID. It would register a second Editor/Default handler for `.tex` and `.md` on this Mac.

## Sequencing and dependencies

1. Step 1 (UX) can land now. It depends on nothing.
2. Name review (coordinator). This gates everything after it.
3. Coordinator decides whether the bundle ID changes. That decides whether steps 4 and 5's release notes are needed.
4. Backend changes the display name / bundle ID (step 3), together with UX steps 4–5. Art supplies the icon and Brag the screenshots at the same time.
5. UX validation (below) runs on a packaged build before release.

## Validation that proves completion

- `git grep -n "LibreWeave" -- NativeLatex NativeLatexTests` returns only the internal identifiers listed above. There are no hits in user-facing strings.
- The built app shows the approved name in About, Hide, Quit, the Settings window title, the Dock, Finder Get Info, and Open With. VoiceOver reads the app name and the BB-8 control in both appearances. Check that VoiceOver's pronunciation of "Virgule" is acceptable.
- Every error string from step 1 shows the bundle name. Trigger at least the not-UTF-8 open, Build in an unsafe folder path, and Convert with Pandoc missing.
- `plutil -extract CFBundleDocumentTypes` gives output identical to the current build's.
- On a Mac that has the old build installed, with appearance set to Dark and `.md` set as the default: install the new build and launch it. Expected results:
  - The appearance is still Dark.
  - `open -g -a <app> notes.md` and `article.tex` (temporary files) open as editable documents.
  - The old preferences domain is unchanged.
  - With an unchanged bundle ID, the Finder default and Open Recent are unchanged too. With a changed bundle ID, the default and recents behave as the release note describes.
- The existing `AppearanceTests`, `NewDocumentTests`, and Integrations copy tests pass with name-agnostic assertions.

## Migration and rollback risks

- **Bundle ID change.** This is the biggest UX risk. Defaults, recents, and window state reset. Appearance can be carried over (step 4); Finder defaults and recents can't. Keeping `app.libreweave.LibreWeave` avoids all of it, at the cost of an old brand inside a mostly invisible ID.
- **Two apps installed side by side.** If the old app stays in `/Applications` with a new ID, both claim `.tex`/`.md` as Default and Finder may pick either one. The release must replace the old app, not install next to it (Backend).
- **Rollback after a rename ships.** Reinstalling the old build reads the old preferences domain, which was never written to, so the user's settings come back. Choices made only in the new build are lost. Build folders stay owned only because the token chain carries the token in both directions; Backend must confirm this.
- **Stale copy.** A missed hard-coded string would show two names side by side. The grep check above catches it.

## Decisions for the coordinator

1. Is Virgule approved after a proper name review, and who runs that review? Until it is, the hold stays in place.
2. Bundle ID: keep `app.libreweave.LibreWeave` (recommended for continuity) or change it (step 4 plus release-note text)?
3. Can step 1 (one app-name source) land now, independent of the name decision?
4. If the bundle ID changes, should a one-time in-app notice about Open With / Change All ship, or only the release note? I recommend only the release note.
5. If Virgule is rejected, which candidate comes next, or does LibreWeave stay?
