# Virgule candidate: integrations plan

Status: planning only · 2026-11-18 · Mac only · source of truth: `main` at `840319f`

Virgule is a candidate name. It is not cleared and not approved. This plan renames nothing and publishes nothing. The shipping brand on `main` is **LibreWeave** (bundle ID `app.libreweave.LibreWeave`, module `LibreWeave`). The integration package keeps the older internal name `NativeLatexIntegrations`.

## Name gate

- **Public-rename hold.** An existing iPhone/iPad news app is named Virgule (App Store ID 1245101112), and a preliminary search found a Canadian VIRGULE trademark listing that mentions software. Neither finding has been reviewed. This plan does not claim the name is clear, and it does not claim the listing covers this app. Until a proper name review clears the name, no integration string that leaves the Mac may say "Virgule".
- **Reversible internal prototype.** Change only the strings shown in the local UI, from one constant, on a branch. Rolling back means reverting one commit or changing one value.
- **Fallback if Virgule is rejected.** Keep "LibreWeave", or put the next candidate into the same constant. No identifier, file, or provider setting depends on the name, so a fallback costs the same as the first rename.

## Current touchpoints (existing behavior on `main`)

**User-visible strings that name the app** (shown in alerts and open panels):

| File:line | String |
| --- | --- |
| `NativeLatex/Integrations/Sources/NativeLatexIntegrations/Conversion.swift:54` | "LibreWeave needs \(tool) for this conversion…" |
| `…/Conversion.swift:56` | "LibreWeave cannot convert…" |
| `…/Conversion.swift:60` | "…LibreWeave never overwrites a previous copy." |
| `…/Process.swift:42` | "LibreWeave could not start \(tool)…" |
| `…/GoogleDocs.swift:31` | "Google Docs is turned off in LibreWeave…" |
| `…/GoogleDocs.swift:33` | "Google sign-in is not available in this LibreWeave build yet…" |
| `…/LibreTexts.swift:24`, `:28`, `:30` | LibreTexts URL, response, and license errors |
| `NativeLatex/App/Conversions.swift:19` | "…was not saved, so LibreWeave stopped…" |
| `NativeLatex/App/Conversions.swift:103` | Import Copy open-panel message |

**Sent to an external service:** `…/LibreTexts.swift:46` sets `User-Agent: LibreWeave/0.1 (local import)` on every request to the public LibreTexts Deki API.

**Tests that assert the brand:** `NativeLatex/Integrations/Tests/NativeLatexIntegrationsTests/ConversionTests.swift:139` ("LibreWeave needs Pandoc"), `…/ProviderTests.swift:38` and `NativeLatexTests/IntegrationTests.swift:29` ("not available in this LibreWeave build"), and `NativeLatexTests/IntegrationTests.swift:3` (`@testable import LibreWeave`, which belongs to the Backend module rename).

**Docs and comments:** `NativeLatex/Integrations/README.md:3` and the doc comment at `…/GoogleDocs.swift:3`.

**Internal names that already avoid the brand.** None of these change:

- Package, product, and module `NativeLatexIntegrations` (`NativeLatex/Integrations/Package.swift`). The Xcode reference is at `NativeLatex.xcodeproj/project.pbxproj:11,82,121,271,277`.
- Temp directory prefixes `nativelatex-convert-`, `nativelatex-proc-`, `nativelatex-libretexts-`, `nativelatex-gdocs-`, and `nativelatex-test-`. They live in `$TMPDIR` and are deleted after each run.
- The opt-in test variable `NATIVELATEX_LIVE_NETWORK` (`ProviderTests.swift:130`).
- The imported UTIs in `LibreWeave-Info.plist` (`org.tug.tex`, `net.daringfireball.markdown`, `org.tug.bib/sty/cls`). These are third-party identifiers, not ours.

**Auth and config identifiers.** None exist. No OAuth client ID, redirect URI or URL scheme, Keychain item, `UserDefaults` key, or provider app registration ships. `Conversions.googleDocs` is a constant `GoogleDocsIntegration(enabled: true)` with no live transport, and its status is always `.liveNotConfigured`. Microsoft/OneDrive is not implemented.

## Cross-format data guarantees (existing, must hold through any rename)

The app writes no brand into user files. Checked in `Conversion.swift`:

- Output names are `<stem>.<ext>` or `<stem> 2.<ext>`. Media folders are `<stem>_media/`. No app name appears in paths.
- Pandoc is not passed `--metadata`, a generator name, or a reference DOCX that carries our name. Pandoc's own `generator` meta in HTML names Pandoc, not the app.
- The LibreTexts attribution (`LibreTexts.swift:97`, `Conversions.swift` `attribution`) names the page, authors, license, and URL, not the app.
- The source file is never modified, and an existing copy is never overwritten (`destinationExists`).

Because of this, a rename has no effect on files already exported or imported, and no migration of user files is needed. The rename must keep this property: no "Exported by Virgule" stamp, no app-named metadata, no app-named media folder.

## Smallest complete change set (prototype, on a branch, after coordinator approval)

1. In `Process.swift`, add one internal constant `let appName = "LibreWeave"`. Replace "LibreWeave" with it in the nine package strings listed above (Conversion ×3, Process ×1, GoogleDocs ×2, LibreTexts ×3); edit the GoogleDocs doc comment as plain text. Keep the constant internal; the package has one consumer.
2. Make `appName` public, or pass it in, so `Conversions.swift:19` and `:103` use the same value. Otherwise those two lines are edited by hand. Coordinator decides (D2).
3. Change the three test assertions so they check text without the brand ("needs Pandoc", "not available in this") or interpolate `appName`. They then survive any later rename.
4. Leave `User-Agent` at `LibreWeave/0.1` while the public hold stands. Change it only at public release, together with the bundle ID (D3).
5. Update `NativeLatex/Integrations/README.md:3` and the "Implemented" paragraph in `docs/workspaces/integrations/integrations.md` only when the public name is approved.

For the internal prototype, set `appName` to "Virgule". Nothing else in the package changes.

Not needed: renaming the package or module, the temp prefixes, or the env var. Those changes are churn that users never see. The Xcode project already links the package by relative path, so a Backend target rename does not touch it.

## Sequencing and dependencies

1. Coordinator approves the internal prototype. Backend renames the app module (`@testable import LibreWeave` → new module). `IntegrationTests.swift:3` follows Backend's change and is not done here.
2. Integrations makes steps 1–3 on the prototype branch.
3. UX approves the wording of the alert and panel copy, so these strings match the rest of the app's voice.
4. **Hold:** steps 4–5 and any provider-facing names wait for the name review to clear and the release to be scheduled by Backend and Landing.
5. **Future connectors (planned, not built):** when Google or Microsoft sign-in is built, register the OAuth consent-screen and app-registration display name only after the name is cleared. Use a loopback redirect, not a custom URL scheme derived from the bundle ID. Use a Keychain service string that does not contain the brand, so a later rename never strands a token or forces the user to sign in again.

## Validation that proves completion

- `git grep -n LibreWeave -- NativeLatex/Integrations NativeLatex/App/Conversions.swift` returns only the `appName` definition and the held `User-Agent`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` in `NativeLatex/Integrations` passes: 17 pass and 1 live test is skipped, as on `main`. The `xcodebuild test` app suite passes `IntegrationTests` under the renamed module.
- Manual check in the built app:
  - Export Copy ▸ Word with Pandoc hidden from `PATH` shows the missing-tool alert with the prototype name.
  - Google Docs: Not Connected… shows the prototype name.
  - Import LibreTexts Page with a non-LibreTexts URL shows the prototype name.
- Data check: export the shared fixtures from `docs/research/conversion-fixtures` before and after the change. Then confirm that the output file names, `_media/` folder names, and DOCX `docProps/*.xml` and HTML `<meta>` contain no app name. `unzip -p out.docx docProps/app.xml docProps/core.xml | grep -i -e libreweave -e virgule` should print nothing.
- With `NATIVELATEX_LIVE_NETWORK=1`, the live LibreTexts test still passes, and the outgoing `User-Agent` is still `LibreWeave/0.1` while the hold stands.

## Migration and rollback risks

| Risk | Severity | Handling |
| --- | --- | --- |
| Data in user files | None found | The app writes no brand into outputs. The validation step above guards against a regression. |
| Settings, tokens, or provider registrations | None today | Nothing is stored. Future connectors must use brand-free Keychain and redirect identifiers (sequencing step 5). |
| Candidate name leaks to LibreTexts | Low, avoidable | Keep the `User-Agent` held. Leaving it unchanged is the safe default. |
| Tests break on the next rename | Low | Brand-free assertions (step 3). |
| Rollback | Trivial | Revert the one commit, or set `appName` back. Files and settings have nothing to undo. |
| Mixed brand in UI if `Conversions.swift` is edited separately | Low | Use the shared constant (D2) or edit both in the same commit. |

## Decisions for the coordinator

- **D1.** Approve an internal prototype branch with `appName = "Virgule"`, or wait for the name review.
- **D2.** Expose one `public` `appName` from the integrations package for the app to reuse, or have the app keep its own two literals or read `CFBundleDisplayName`. Recommendation: public constant. It is the smallest change and works in `swift test`, where `Bundle.main` is the test runner.
- **D3.** Confirm the `User-Agent` stays `LibreWeave/0.1` until the public release.
- **D4.** Confirm the internal `NativeLatexIntegrations` and `nativelatex-*` names stay. Recommendation: they stay.
- **D5.** Fallback name if Virgule is rejected. It drops into the same constant at no extra cost.
