# Backend plan: Virgule candidate rename

Status: planning only · 2026-11-18. Source of truth: `main` at `840319f`. Virgule is a **candidate** name. This plan renames nothing and changes no code, bundle, installation or release.

## Name gate (applies to every step below)

- **Public-rename hold.** An iPhone/iPad news app is already called Virgule (App Store ID 1245101112), and a preliminary search found a Canadian VIRGULE trademark listing that mentions software. Nobody has shown that the name is cleared, or that the listing does or does not cover this app. Until a proper name review approves it, Virgule must not appear in a bundle identifier, product or executable name, scheme, signed or notarized artifact, download, or release note.
- **Reversible internal prototype** (allowed before review): change only the name shown on this Mac. See Phase 0.
- **Fallback if Virgule is rejected:** revert the Phase 0 commit and keep LibreWeave, or run Phase 1 with a different name. Phase 1 deliberately does not depend on the name, so rejecting Virgule wastes only Phase 0.

## Current touchpoints (existing behavior)

| Area | Where | Current value / behavior |
| --- | --- | --- |
| Target, product, executable | `NativeLatex.xcodeproj/project.pbxproj` (targets `LibreWeave`, `LibreWeaveTests`; Debug and Release) | `PRODUCT_NAME = LibreWeave` → `LibreWeave.app/Contents/MacOS/LibreWeave` |
| Display name | same, `INFOPLIST_KEY_CFBundleDisplayName = LibreWeave` (Debug and Release) | Menu bar, Dock, Finder name |
| Bundle ID | same, `PRODUCT_BUNDLE_IDENTIFIER` | App `app.libreweave.LibreWeave`; tests `app.libreweave.LibreWeaveTests` |
| Swift module | same, `PRODUCT_MODULE_NAME = LibreWeave`; `@testable import LibreWeave` in all `NativeLatexTests/*.swift` | Not visible to users |
| Test host | same, `TEST_HOST = $(BUILT_PRODUCTS_DIR)/LibreWeave.app/Contents/MacOS/LibreWeave`, `BUNDLE_LOADER` | Breaks if `PRODUCT_NAME` changes and this does not |
| Scheme | No shared `.xcscheme`; Xcode generates `LibreWeave` from the target name | `docs/deployment-plan.md` archive command uses `-scheme LibreWeave` |
| Info.plist | `LibreWeave-Info.plist` (repo root; named in pbxproj `INFOPLIST_FILE` and a comment in `NativeLatex/App/BuildService.swift:44`) | Document types and imported UTIs (`org.tug.*`, `net.daringfireball.markdown`, `public.plain-text`). Contains no brand string. |
| Entry point | `NativeLatex/App/LibreWeaveApp.swift` (`struct LibreWeaveApp`) | Code identifier only |
| Preferences | `UserDefaults.standard` = domain `app.libreweave.LibreWeave` | Holds `appearanceMode` (BB-8 control, from `NativeLatexDesign/AppearanceStore.swift`) and `buildOwnerToken`, plus system keys (`NSOSPLastRootDirectory`, window frames) |
| Earlier migration | `BuildService.legacyDefaultsDomain = "app.libreleaf.LibreLeaf"` (`BuildService.swift:57`); `LibreWeaveApp.migrateAppearance` (`LibreWeaveApp.swift:16`); `BuildService.ownerToken(in:legacy:)` (`BuildService.swift:61`) | Reads one older domain, read-only. Only a valid UUID token or a known appearance value is copied, and a value already in the current domain wins. Tests: `AppearanceTests.testAppearanceChoiceMigratesFromLibreLeafDomain`, `BuildSafetyTests.testOwnerTokenMigratesFromLibreLeafDomain`. |
| Build output | `BuildService.buildFolderName = ".libreleaf-build"`; marker `.libreleaf-owner`; `LibreLeaf.log` (`BuildService.swift:41,124,153`) | Lives in users' project folders. Ownership is proven by the token in the marker. Kept under the old name on purpose so existing output stays owned. |
| Ephemeral internals | `MarkdownPreview.swift` (`libreleaf-local` URL scheme, `libreleaf-preview-*` temp dir); `NSAttributedString.Key("LibreWeaveMarkdown*")` in `MarkdownWriter.swift` and `MarkdownObjects.swift`; `.libreWeaveTheme()` in the Design package | Never written to user files or preferences |
| User-facing strings | `TextDocument.swift`, `BuildService.swift:31,33`, `Conversions.swift`, `MarkdownPreview.swift:92`, `LibreWeaveApp.swift:334`; Integrations sources | Owned by the UX and Integrations plans. Listed here only because a backend phase must not ship half-renamed. |
| Test-only names | `LIBREWEAVE_SNAPSHOT_DIR`, `libreweave.test.<uuid>` suites, `libreleaf-markdown-*.png` | Safe to rename at any time |
| System state keyed by bundle ID (observed on this Mac) | `~/Library/Application Support/com.apple.sharedfilelist/…ApplicationRecentDocuments/app.libreweave.libreweave.sfl4` (and a leftover `app.libreleaf.libreleaf.sfl4`); Saved Application State; Launch Services default-handler choices | Bound to the bundle ID, so they do not follow a bundle ID change |
| Installed copies | `~/Applications/LibreWeave.app`, `dist/LibreWeave.app` (git-ignored). `lsregister -dump` also lists stale `LibreLeaf.app` builds under `/private/tmp`. | Ad-hoc signed, Hardened Runtime, universal, version 0.1 build 2 |
| Signing and release | Manual signing, `CODE_SIGN_IDENTITY = "-"`; Release has `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`; no team; keychain has 0 valid identities | No Developer ID build, notarization, ZIP, or download exists |

No app-owned Application Support files, Keychain items, OAuth client IDs, App Groups or entitlements exist yet. `GoogleDocs.swift` says it has no OAuth client and no Keychain storage. The Integrations plan owns those identifiers if they are added later.

## Smallest complete change set

### Phase 0: internal prototype (reversible, allowed under the hold)

1. Set `INFOPLIST_KEY_CFBundleDisplayName = Virgule` in the app target's Debug configuration only, on a prototype branch.
2. Leave everything else unchanged: bundle ID, product, executable, module, scheme, preferences, build folder and Release.

Result: Debug runs show "Virgule" in the menu bar and Dock. The bundle ID, preferences, recent documents, file associations and build output are all untouched, so nothing needs migrating. Rollback is one reverted line. Never archive or distribute a Phase 0 build.

### Phase 1: decouple identity from the name (independent of the name review)

Take this step only if the coordinator decides the bundle ID should change at all (Decision 1). The app has not been released, so this is the cheapest moment to change it.

1. **Bundle ID:** move to a name-neutral ID under a domain the owner controls, e.g. `com.ayushmadhav.<stable-slug>` (the landing site already uses that domain). Do the same for the test bundle. Then a later rename, including the fallback, never needs a third preferences migration.
2. **Migration chain:** replace the single `legacyDefaultsDomain` with an ordered list, newest first: `["app.libreweave.LibreWeave", "app.libreleaf.LibreLeaf"]`. `migrateAppearance` and `ownerToken` take the first acceptable value. Keep the current rules: read-only, current domain wins, UUID-only token, known appearance values only. The token must carry over, otherwise existing `.libreleaf-build/<stem>-<token8>` folders become foreign and builds stop with `unownedOutputDirectory`. The guard prevents data loss, but it still interrupts the user.
3. **Do not rename** `.libreleaf-build`, `.libreleaf-owner` or `LibreLeaf.log`. They are hidden, already exist in user folders, and are covered by safety tests. Renaming them would leave orphaned output and require a second ownership scheme. If a name change is ever wanted, it should be a new and separate decision.

### Phase 2: public rename (only after the name review approves)

1. pbxproj: set `PRODUCT_NAME` and the target names to `Virgule`/`VirguleTests`, and update `TEST_HOST`/`BUNDLE_LOADER` to `Virgule.app/Contents/MacOS/Virgule` and `INFOPLIST_KEY_CFBundleDisplayName` in Debug and Release. Rename `LibreWeave-Info.plist` to `Virgule-Info.plist`, plus its pbxproj reference and the comment at `BuildService.swift:44`.
2. Module: keep `PRODUCT_MODULE_NAME = LibreWeave` (no user impact, no churn), or rename it together with every `@testable import` (Decision 3).
3. Optional cleanup in the same commit: `LibreWeaveApp` becomes `VirguleApp` and the ephemeral internal identifiers get renamed. These are safe, but nothing requires them.
4. Docs: update the archive command and scheme in `docs/deployment-plan.md` and the identity line in `docs/status.md`.
5. Release: bump `CURRENT_PROJECT_VERSION`. Archive the new scheme, then sign with Developer ID, notarize and staple through Organizer as in `docs/deployment-plan.md`. The rename adds no new signing step. Bundle IDs for Developer ID apps without App Store capabilities normally need no App ID registration; confirm this in the owner's account at signing time.

## Sequencing and dependencies

1. Phase 0 can start immediately and depends on nothing.
2. Phase 1 needs Decision 1. It must land **before the first Developer ID release**, because after a public release every bundle ID change also strands other users' preferences.
3. Phase 2 needs name review approval, Phase 1 if Phase 1 was chosen, and the UX/Integrations string changes in the same release so the shipped app is not half-renamed. Art provides `AppIcon.icon`. The icon path does not depend on the name.
4. Installed-app replacement on this Mac comes after the Phase 1 or Phase 2 build:
   1. Quit the app.
   2. Move `~/Applications/LibreWeave.app` to a dated backup outside `/Applications` and `~/Applications`, the same way `/private/tmp/LibreLeaf.app.old-20261117` was handled.
   3. Run `lsregister -u` on the old path.
   4. Install the new app and open it once.
   5. Set the default app for `.tex` and `.md` again in Finder (Get Info ▸ Open with ▸ Change All). Two apps with the same bundle ID registered at once confuse Launch Services, which is why the old copy is unregistered first.

## Validation that proves completion

| Phase | Proof |
| --- | --- |
| 0 | `plutil -extract CFBundleDisplayName raw` on the Debug app prints `Virgule`. `CFBundleIdentifier` is unchanged. `defaults read app.libreweave.LibreWeave` still shows the same `appearanceMode` and `buildOwnerToken`. The full `LibreWeave` test scheme passes. |
| 1 | New unit tests cover the chain: the LibreWeave domain wins over LibreLeaf; LibreLeaf alone still migrates; a malformed token in the newer domain falls through to a valid older one, or to a fresh UUID if none is valid; a value already in the current domain is never overwritten; old domains are unchanged afterward. The existing migration tests are generalized, not deleted. A manual check on this Mac: launch the new bundle ID, confirm the BB-8 choice persists, then build an existing `.tex` folder and confirm it **reuses** its `.libreleaf-build/<stem>-A9E73C58` folder with no `unownedOutputDirectory` error. |
| 2 | `xcodebuild -scheme Virgule test` passes the full suite. `grep -rniE 'libreweave'` over `NativeLatex/App`, the pbxproj and the plist finds only the documented legacy-domain strings (and the module name if it was kept). `plutil -extract CFBundleDocumentTypes` matches the current plist. On the archive: `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute` all pass. On a clean Mac, the downloaded ZIP opens `.tex`, `.md` and `.txt` through Open With, and the TeX-absent state appears. |

## Migration and rollback risks

- **Lost recent documents and window state.** Both are keyed by bundle ID, and macOS does not migrate them. Accept this and tell the user (UX copy), or keep the bundle ID. Do not write into `com.apple.sharedfilelist` files; their format is private.
- **Default-handler loss.** After the old app is removed, `.tex`/`.md` fall back to another app until the user re-chooses. Install adds the app to Open With but cannot silently become the default.
- **Owner token.** If the token is not migrated, existing build folders are refused, though never deleted. The migration chain plus the manual reuse check covers this.
- **Rollback after Phase 1.** The old app still reads its untouched old domain, so reinstalling the backup `.app` restores the previous state. Settings changed in the new app do not flow back. The migration is read-only by design, which keeps rollback safe.
- **Rollback after a public release.** Users' preferences then live in the new domain. Rolling back means keeping the new bundle ID and changing only the display name. This is why the hold exists.
- **Duplicate bundle IDs on disk.** Old Debug builds under `/private/tmp` and `dist/` are still registered with Launch Services. Unregister or delete them before testing the default-handler behavior.
- **Signed release with the wrong identity.** If Phase 2 ships before Phase 1 is settled, the bundle ID is fixed for all future users. Phase 1 therefore comes first.

## Decisions for the coordinator

1. **Change the bundle ID at all?** Recommended: yes, once, to a name-neutral ID before the first Developer ID release. Alternative: keep `app.libreweave.LibreWeave` for good. That costs no migration, but the ID keeps an old name that is never shown to users.
2. **Which name-neutral ID?** For example `com.ayushmadhav.<slug>`. It must be a domain the owner controls and a slug that is not a product name.
3. **Rename the Swift module and target, or only the product?** Recommended: product, target and scheme yes. Module is optional.
4. **Keep the `.libreleaf-*` build folder names?** Recommended: yes, permanently.
5. **Who runs the name review, and what evidence approves Phase 2?** This plan does not settle that, and it does not assess the App Store or Canadian listings.
6. **Fallback name** if Virgule is rejected. Phase 1 works unchanged with any name.
