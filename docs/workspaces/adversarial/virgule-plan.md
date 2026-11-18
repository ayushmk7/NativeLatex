# Adversarial: Virgule candidate rename plan

**Status:** planning only, revised 2026-11-18. Virgule is a candidate name, not an approved one. Nothing here renames code, assets, bundle IDs, installed apps, URLs or releases. Source of truth: `main` at `65542e6` (the brief commit on top of `840319f`).

**What this revision reviews.** The first pass (`86ec1ec`) reviewed Art's obsolete keep-the-weave plan (`b41a39e`). This pass reviews the plans that now sit **uncommitted** in the main checkout's working tree: the coordinator plan `docs/virgule-rebrand-plan.md` and the seven other workspace plans under `docs/workspaces/{art,ux,backend,integrations,markdown-ux,brag,landing}/virgule-plan.md`. The Art copy is byte-identical to `d385d7b` (the new slash icon). This file is the eighth plan.

Findings marked **[evidence]** were checked on this Mac or in `main`. Findings marked **[risk]** are reasoning that still needs a test. **[uncertain]** marks a claim I could not settle and that needs a qualified person.

## Critical findings (read these first)

1. **[risk] Art's Clear light gate passes by construction and does not test the real failure.** Art's own measurements (`art/README.md:14-27`) show the Clear sheet in static renders is a fixed neutral glass: 128 in Clear light, 43–44 in Clear dark, and fill, glass and translucency settings never change it. Mono lines render white there. A white Mono slash will therefore measure about 255 − 128 = 127 in Clear light, roughly double Art's "≥ 60" gate, before any design work. The gate cannot fail. The real Clear light risk is the **live Dock**: macOS composites backdrop translucency there (`art/README.md:27`, `review.sh:8`), so over a bright wallpaper the glass gets lighter than 128 and the white slash loses contrast. The weave survives that with three tones (sheet < threads < lines). A slash has two, so nothing else carries the shape. Art also keeps `shadow none` and `specular false` (`d385d7b` Phase 1 step 2), which drops the edge cues the system could otherwise add. `appearance-check` and `ictool` flatten Clear onto the neutral glass, so no part of Art's acceptance table can see this. **Add a gate:** a Dock screenshot in Clear light over a white or very light wallpaper and over a mid-grey one, at the default Dock size and at the smallest Dock size, compared next to Apple's Calculator and Notes in the same Dock. Capture it with `screencapture -R` of the Dock region only, with the app launched by `open -g` (no focus steal). If the slash fades below Apple's icons there, try specular on, or a Mono-only shadow, in the prototype before accepting the brief. Keep the static "≥ 60" row, but say it is a regression check, not a legibility proof.
2. **[evidence/risk] Tinted rows have thin or no baselines.** "White (Mono)" does not stay white in Tinted. The weave's white lines measured **97** on a **36** sheet in Tinted dark (`art/README.md:20`). A white slash is likely to land near the same value: 97 − 36 = 61, only 11 above Art's "≥ 50" gate, and that figure is from a 1024 px render. At 16 px the stroke is about 2.3 px wide (150 px on the 1024 grid), so anti-aliasing will pull its centre down, and the 16 px Tinted dark check Art requires may fail. Tinted light has **no measurement at all**: `art/README.md` has no Tinted light row, so Art's "≥ 50" target there is a guess. Both need prototype numbers before the brief is approved. If 16 px Tinted dark fails, the fix is a wider stroke (for example 170–180 px), not a weaker gate.
3. **[uncertain] The SF Pro wordmark licence is not settled, and the plan should not assume it.** Art Phase 1 step 4 still plans "Virgule" in **SF Pro Bold**, with an outlined export, for the landing lockup, README and media. What I found:
   - The downloadable SF Pro font from Apple's developer site is reported, in Apple developer forum quotes of its installer note, to be licensed "solely for creating mock-ups of user interfaces to be used in software products running on Apple's iOS, iPadOS, macOS or tvOS operating systems". I did not read the current licence PDF in the download itself.
   - The copy on this Mac is `/System/Library/Fonts/SFNS.ttf` ("System Font"). Its name table says use "is subject to the terms of the applicable OS Software License Agreement", and its `fsType` is `0x0` (no embedding restriction bits). The OS licence on this Mac (`/Library/Documentation/License.lpdf`) is a **pre-release seed** licence. It covers fonts as part of the "Apple Software" and grants no separate right to use them in logos.
   - `fsType 0` is a technical embedding flag. It is not a licence grant, and it says nothing about trademark use. "San Francisco" is also an Apple trademark (name ID 7).

   So an outlined SF Pro wordmark used as a public logo, on a website or in a video, **may** fall outside both licences. I can't confirm that it does, and this is not legal advice. Either the coordinator gets a qualified answer, or the wordmark uses an openly licensed face (SIL OFL fonts such as Inter allow logo use and outlining). The live landing `<span>` that uses the visitor's own system font stack (`landing/styles.css:15`) does not raise this question. **Recommended:** no outlined wordmark until this is settled; keep the span (Art decision 3).
4. **[evidence] The last rename already lost the build-owner token, and the coordinator plan still lacks the rule that would prevent a repeat.** On this Mac, `defaults read app.libreweave.LibreWeave buildOwnerToken` is `A9E73C58-…` and `app.libreleaf.LibreLeaf` holds `296CB858-…` (rechecked in this revision). The bundle ID changed in `93cef0f` (12:28) and the migration landed in `23681df` (12:37). A build or test run in those nine minutes wrote a fresh token, and "current token wins" then blocked adoption for good. LibreLeaf-era `.libreleaf-build/<stem>-296CB858` folders are orphaned (never deleted, never reused). The coordinator plan says "migrate … from LibreWeave then LibreLeaf" (`virgule-rebrand-plan.md:10`) and Backend Phase 1 lists the chain, but neither says it must land **in the same commit** as the bundle-ID change, with no intermediate commit built or tested. App tests run inside the app host (`project.pbxproj:233,244`) and call `BuildService.ownerToken` (`BuildSafetyTests.swift:37`), so one `xcodebuild test` in between repeats the loss.
5. **[evidence] The UX prototype path is unchanged and still wrong.** It still says a same-ID build means "nothing new registers with LaunchServices". `lsregister -dump` on this Mac lists about 40 registered LibreWeave/LibreLeaf bundles (`dist/`, `~/Applications/`, five in `~/.Trash/`, many under `/private/tmp` and `$TMPDIR`), each claiming `.tex`/`.md` at rank `Default`. A command-line `PRODUCT_NAME` override also breaks the test action, because `TEST_HOST` is hard-coded to `LibreWeave.app/Contents/MacOS/LibreWeave`. My `plutil`-copy prototype below avoids both problems.
6. **[risk] The fallback "keep LibreWeave" still assumes LibreWeave is clear.** The coordinator rollback ("If the name review rejects Virgule … keep LibreWeave live", `virgule-rebrand-plan.md:48`) and every workspace fallback assume this. LibreWeave has had no name review. It sits next to LibreOffice (invoked as `soffice`, `Process.swift:25`) and LibreTexts (an integration). Coordinator decision 1 should cover both names in one review.
7. **[evidence] Never rename `.libreleaf-build`, `.libreleaf-owner`, `LibreLeaf.log`** (`BuildService.swift:41,124,153`, `.gitignore:3`). All eight plans now agree on this. Exclude them, the `libreleaf-local://` scheme, and the temp prefixes from every stale-brand grep.
8. **[evidence] There is no public release, signing identity or notarized build** (`docs/status.md:51`, `docs/deployment-plan.md:36`). If the bundle ID ever changes, it must change before the first Developer ID release. Decide the final ID together with signing, not with the display name.

## Coordinator inconsistencies

The coordinator plan and the workspace plans disagree in the places below. Each needs one recorded decision before implementation.

| # | Coordinator says | Workspace plan says | Recommendation |
| --- | --- | --- | --- |
| C1 | Keep bundle ID `app.libreweave.LibreWeave` (recommended, `:10`) | Backend decision 1: **yes, change once** to a name-neutral `com.ayushmadhav.<slug>` | Pick one. I recommend keeping it: there are no external users, and the same-commit risk (finding 4) and the second-Default-handler risk disappear. |
| C2 | Step 3: rename "Swift module and `@testable import` callers together"; "rename the plist path if chosen" | Backend decision 3: module optional; Backend Phase 2 renames `LibreWeave-Info.plist`. Integrations sequencing step 1 expects a module rename. | Keep `PRODUCT_MODULE_NAME = LibreWeave` and the plist name. Nobody sees them, and renaming them touches every test file for no user benefit. |
| C3 | Step 1: Art explores "at least two genuinely new slash-mark treatments" | Art has one brief ("One mark", decision 2: approve 150 px, 65–70°, rounded caps) | Either Art adds a second treatment to Phase 1, or the coordinator drops "at least two". Given findings 1–2, a second treatment with a wider stroke (or square caps) is worth having. |
| C4 | Step 3: "Do not add a cross-package naming layer solely for a one-time replacement" | UX step 1 adds a `Bundle.main` `appName`; Integrations D2 recommends a public `appName` constant; Markdown UX neutralizes its one string instead | The coordinator rule is right. `Bundle.main` is the `xctest` runner under `swift test` (Integrations confirms this). Do a literal swap, and use brand-neutral copy where it reads well (the Markdown UX approach). |
| C5 | Step 5/6 does not decide media file names | Brag decision 4: rename to a brand-neutral prefix in one commit. Landing decision 4 and Art decision 4: keep `libreweave-*` until redirects are live. | Keep `libreweave-*`. `README.md:15-16` hard-links the MP4 on the old host, and Pages cannot 301 it. |
| C6 | Decision list (`:50`) does not include the LibreWeave review | — | Add it (finding 6). |
| C7 | Workspace table links `workspaces/adversarial/virgule-plan.md` | That file does not exist in the main checkout (the other seven are untracked copies there) | Copy this plan in with the others, or the link is broken. |
| C8 | Completion evidence: "built icon … inspected at small sizes in default/light, dark, clear and tinted styles" | Art gates are static renders only | Add the live-Dock Clear light check (finding 1). |
| C9 | Step 6: "Prepare the new hostname" before the cutover window | Landing: add the DNS record only after approval, because DNS publishes the name | Follow Landing. The coordinator's wording should say "after approval". |

Backend Phase 0 (display name only, Debug) also claims the menu bar shows "Virgule". The app menu (About/Hide/Quit) is usually titled from `CFBundleName` (= `PRODUCT_NAME`), not `CFBundleDisplayName` **[risk]**. Phase 0's validation only checks `plutil`. Check the running app's menu bar too.

## Art (`d385d7b`): the new slash icon

**Agreed:**
- One solidus on the system squircle, with no inner rect, frame or backing shape. This fixes the box-in-box problem.
- `#2563EB` stays the only blue. The `AccentColor`, `Theme.swift` and BB-8 stay unchanged.
- The slash is drawn from scratch in `gen.py`, not taken from a font glyph.
- The Mono specialization uses a white slash. That is right: blue in Mono measured 53 on a 36 sheet with the weave.
- The weave is kept only behind a tag. Art's public hold matches the other plans.

**Contrast numbers checked.** The relative luminance of `#2563EB` is about 0.153. Against white that gives 1.05 / 0.203 = **5.17:1**, and against `#0A0A0A` (luminance about 0.003) it gives 0.203 / 0.053 = **3.83:1**. Art's Light and Dark targets are correct. Dark clears WCAG 1.4.11 (3:1 for graphics) with little margin, and a 16 px anti-aliased stroke will sit below the 256 px value. Measure Dark at 16 px too, not only at 256.

**Geometry checked.** The line from (604, 262) to (420, 762) runs at about 70° and is about 533 px long. With 75 px rounded caps it spans y = 187–837 and x = 345–679, inside the 100–924 body and clear of the 185 px corner radius. That meets "never touches the sheet edge". The stroke is 2.34 px wide at 16 px, just over Art's 2 px minimum (see finding 2).

**Corrections to Art's plan:**
- **Clear light gate:** see finding 1. As written, it can't fail.
- **Tinted gates:** see finding 2. Tinted light has no baseline, and Tinted dark has about 11 points of margin at 1024 px.
- **Wordmark in SF Pro:** see finding 3. My first pass stated the licence limit as fact. This pass corrects that to **uncertain, needs a qualified answer**. Either way, the recommendation stays the same: no outlined SF Pro wordmark in public assets until it is settled.
- **"Exactly one `<rect>`" check:** it says "the generated layer SVGs and `landing/icon.svg` contain exactly one `<rect>`", then says layer files contain only the path. As a count it should read: `landing/icon.svg` and `art/source/app-icon-*.svg` have exactly one `<rect>` (the sheet, as today: `landing/icon.svg` has `<rect x="100" y="100" width="824" height="824" rx="185">`); `mark-*.svg` and the `.icon` layer SVGs have zero.
- **Correction to my first pass:** I said the favicon carries no brand except its `aria-label`, so it should not gate Landing. With a new mark, the favicon's pixels change, so Landing's cutover does need it. The **wordmark** still should not gate Landing if the header keeps the text span.
- **Mark clearance:** Art asks the name review to compare the slash with the Virgule news app's icon. I have not seen that icon. Record it in the review; don't assume either way.
- **Prototype exposure:** `art/prototype/virgule/` must stay on the branch. Merging it makes the name public in the GitHub repo even though Pages won't publish it.
- **Rollback tag:** `art-libreweave-weave` is fine locally. Pushing it is harmless, since it only names the old brand.

## Name viability (challenge, not clearance)

- **App Store:** Virgule (ID 1245101112, iPhone/iPad news) is recorded in every plan. I did not verify it independently. Developer ID distribution doesn't need a unique App Store name, but a future Mac App Store listing, and search, could collide.
- **Trademark:** a Canadian VIRGULE listing that mentions software is recorded. My web searches on 2026-11-18 found nothing more. That is **not clearance**: the review needs direct searches of USPTO, EUIPO/TMview, WIPO and CIPO in classes 9 and 42, including variants.
- **Distinctiveness:** "virgule" is a dictionary word (slash in English, comma in French). Expect weak search ranking.
- **Not checked:** domains, GitHub names, VoiceOver pronunciation.

## Current touchpoints (independently checked on `main`)

| Area | Where | Note |
| --- | --- | --- |
| Bundle identity | `project.pbxproj:192-199,213-220`; tests `app.libreweave.LibreWeaveTests` (`:229,240`) | No shared schemes. A target rename silently renames the generated scheme that `deployment-plan.md:20` uses. |
| Test host | `project.pbxproj:233,244`; `@testable import LibreWeave` in six test files | Keep the module name. |
| Migration code | `LibreWeaveApp.swift:10-21`, `BuildService.swift:52-68`; one `legacyDefaultsDomain`, pinned by `BuildSafetyTests.swift:174` | A chain needs an ordered list and a test that pins the order. |
| File associations | `LibreWeave-Info.plist`: `.tex`/`.md` Editor/Default | No brand. Must stay byte-identical. |
| Build output | `.libreleaf-build/<stem>-<token8>/`, `.libreleaf-owner`, `LibreLeaf.log` | Never rename. |
| Icon | `NativeLatex/AppIcon.icon` (sheet fills White / `#0A0A0A` / `#0A0A0A` Mono; no shadow or specular); `art/README.md:14-27` brightness table | Baselines for findings 1–2. |
| Landing | `pages.yml`, `landing/index.html`, `landing/media/libreweave-*`, `localStorage "libreweave-theme"` | Pages has one custom domain and no 301s. Don't rename the theme key. |
| README | absolute MP4 and site URLs (`README.md:15-16`) | They break when the host moves. |

## Smallest complete change set

**Before approval (allowed during the hold)**
1. Nothing lands on `main`. Plans only.
2. **Art prototype (on a branch):** besides Art's static gates, record the live-Dock Clear light screenshots (finding 1) and the 16 px Tinted dark and Tinted light numbers (finding 2).
3. **Name prototype (reversible, on this Mac only):** copy `dist/LibreWeave.app` into a new empty temp directory. Run `plutil -replace CFBundleName -string Virgule` and `plutil -replace CFBundleDisplayName -string Virgule` on its `Info.plist`, then re-sign it with `codesign --force -s - --options runtime`. Open temporary documents only, and don't Build a real project with it. Afterwards, run `lsregister -u` on the copy, delete it, and check that `lsregister -dump | grep Virgule` is empty.

**After approval**
1. `INFOPLIST_KEY_CFBundleDisplayName` and `PRODUCT_NAME` → the approved name, with `TEST_HOST` updated in the same edit. Keep `PRODUCT_MODULE_NAME`, both bundle IDs (unless C1 says otherwise) and the plist name. Update `deployment-plan.md` in the same commit if the scheme name changes.
2. User-facing strings: a literal swap, plus brand-neutral wording where it reads well (C4).
3. Art Phase 2 under the corrected gates. No outlined SF Pro wordmark unless finding 3 is settled.
4. Landing/README copy. Keep the `libreweave-*` media names and the theme key. Keep the old host serving.
5. Media recapture from the renamed build.
6. **Only if the bundle ID changes** (before the first Developer ID release): the ordered chain `[app.libreweave.LibreWeave, app.libreleaf.LibreLeaf]` lands in the **same commit** as the ID change. Back up first with `defaults export app.libreweave.LibreWeave ~/libreweave-prefs-backup.plist`.

## Validation that proves completion

- **No token loss:** `defaults read <id> buildOwnerToken` still starts with `A9E73C58`, and the first build reuses an existing `.libreleaf-build/<stem>-A9E73C58` folder (no sibling folder appears).
- **Icon:** Art's static table passes, **and** the Clear light Dock screenshots over light and mid-grey wallpapers show the slash at least as readable as Apple's Calculator and Notes. Tinted dark passes at 16 px.
- **Wordmark:** either a recorded licence answer for SF Pro or an OFL face. No unreviewed outlined SF Pro file in `art/`, `landing/` or the media.
- `plutil -extract CFBundleDocumentTypes xml1 -o - <app>/Contents/Info.plist` is byte-identical to the current build's.
- The running app's menu bar shows the new name in About, Hide and Quit. Finder, the Dock, Open With and VoiceOver show it too.
- `git grep -n -i libreweave` over app sources, Integrations, `landing/index.html` and `README.md` returns only the agreed exclusion list.
- `xcodebuild test` plus `swift test` in all three packages, pasted locally (no CI runs them).
- `lsregister -dump` shows exactly one installed copy per bundle ID outside the build folders.
- `curl -sI https://libreweave.ayushmadhav.com/media/libreweave-demo.mp4` returns 200 or a 301 chain ending in 200 after the cutover.

## Migration and rollback risks

| Risk | Trigger | Mitigation / rollback |
| --- | --- | --- |
| Slash vanishes in the live Clear light Dock | Light wallpaper; static gates can't see it | Dock screenshot gate; specular or Mono shadow trial; wider stroke |
| Slash too faint in Tinted at 16 px | Mono white maps to ~97 on a 36 sheet | Measure in the prototype; widen the stroke |
| Wordmark licence problem after publishing | Outlined SF Pro on the site or in a video | Settle first, or use an OFL face; rollback means re-rendering the media |
| Token loss, orphaned build folders | ID change and chain land in different commits | Same-commit rule; `defaults import` the backup |
| Two Default handlers for `.tex`/`.md` | New ID while the old app or a Trash copy remains | Keep the ID (C1) |
| Menu still says LibreWeave | Only the display name changed | Change `PRODUCT_NAME` too, and check the running app |
| Dead video/site links | Pages domain moved | Keep the old host serving; Vercel 301 or a second Pages repo |
| Fallback name also contested | LibreWeave never reviewed | Review both names together |

## Coordinator decisions

1. Who runs the name review, which registers and classes count, and does it cover LibreWeave and the slash mark too?
2. Resolve C1: keep the bundle ID (recommended) or change it once before the first Developer ID release, under the same-commit rule.
3. Resolve C2–C5 and C9 as recommended above.
4. Wordmark: get a qualified answer on SF Pro, or choose an OFL face. Recommended: no wordmark for now; keep the text span.
5. Add the live-Dock Clear light gate and the Tinted baselines to Art's acceptance checks before approving Art decision 2 (the brief).
6. Copy this plan into the main checkout next to the other seven (C7).
7. Clean up stale LaunchServices registrations on this Mac before any rename testing. This is local only and needs approval because it touches installed apps.
