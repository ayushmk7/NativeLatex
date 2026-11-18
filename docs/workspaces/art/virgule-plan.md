# Art: Virgule candidate rebrand plan

**Status:** planning only, revised 2026-11-18. The owner asked for a total rebrand, including a new icon. This plan replaces the woven LibreWeave icon with an original slash (virgule) mark. The weave stays in the plan only as the rollback target. Virgule is still a candidate name and is not cleared. This pass implements no art and renames no code, asset, bundle ID, URL, repo or release. Source of truth: `main` at `840319f`. None of the art, landing, icon or theme files differ between `main` and this branch.

## Name gate (blocks all public art)

- An iPhone/iPad news app is already called Virgule (App Store ID 1245101112). A preliminary search also found a Canadian VIRGULE trademark listing that mentions software. Neither has been checked against this app, and neither is cleared.
- **Public hold:** until the coordinator records a passed name review, no Virgule icon, mark, favicon, wordmark, screenshot or video reaches `NativeLatex/AppIcon.icon`, `landing/`, `README.md`, GitHub, or a release.
- **Internal prototype:** the new icon is drafted on a branch in `art/prototype/virgule/`, which neither the build nor the site references. Rollback is deleting the branch.
- **Fallback if Virgule is rejected:** a slash mark only makes sense for this name, so it does not carry over. LibreWeave keeps shipping with the weave unchanged. If the rebrand continues under another name, that name gets a new mark brief held to the same acceptance checks below.
- The name review also covers the mark. A plain slash is a common glyph, so check that it is not confusingly close to an existing software logo, including the Virgule news app's icon.

## Current touchpoints (existing behavior, all replaced)

| Touchpoint | Path | Today |
| --- | --- | --- |
| Geometry generator (single source) | `art/tools/gen.py` | Weave geometry (two lines, two threads), `<title>`/`aria-label` "LibreWeave". Writes every file below. |
| Icon Composer document | `NativeLatex/AppIcon.icon/icon.json`, `Assets/lines-{black,white}.svg`, `Assets/threads.svg` | Light = white sheet, Dark = `#0A0A0A` sheet, Tinted (Mono, also drives Clear) = dark sheet with white lines. Threads are `#2563EB` in every appearance. No glass, shadow or specular. |
| Flat icons and one-color marks | `art/source/app-icon-{white,black}.svg`, `art/source/mark-{white,black}.svg` | Weave |
| Favicon | `landing/icon.svg` | Weave, switching sheet with `prefers-color-scheme`, `aria-label="LibreWeave"` |
| Previews and evidence | `art/exports/*.png`, `review.png`, `built-app-evidence.txt` | Weave renders and `LibreWeave.app` evidence |
| Review and validate tools | `art/tools/{build,validate,review}.sh`, `appearance-check.m` | Measure the *sheet* only, and name a `LibreWeave.app` bundle |
| Brand docs | `art/README.md`, `docs/workspaces/art/art-direction.md` | Describe the weave and the brightness tables |
| Accent | `NativeLatex/Assets.xcassets/AccentColor.colorset` | `#2563EB` universal. **Unchanged.** |
| One-blue consumers | `NativeLatexDesign/Theme.swift:48-49` (Design owns), `landing/styles.css:1,61` | `#2563EB` only. **Unchanged.** |
| BB-8 switch | `landing/bb8.css`, `NativeLatexDesign/BB8Toggle.swift` | Intentional orange exception with the Uiverse.io / Galahhad credit. **Unchanged.** |
| Wordmark | None. The landing header is the icon plus a text `<span>LibreWeave</span>` (`landing/index.html:26-27`). | New |
| Screenshots and video (Brag and Landing own them) | `landing/media/libreweave-*` | Show the weave icon and the LibreWeave name. Recapture. |

Art has nothing in Info.plist, file associations, bundle IDs or preference keys. Backend and UX own those.

## New mark brief

- **One mark:** a single solidus, drawn as one stroke with rounded caps. It sits at about 65–70° from horizontal and is optically centred on the sheet. Proposed starting geometry on Apple's 1024 grid (sheet body 100–924): stroke about 150 px wide, running from about (604, 262) to (420, 762). That makes it about 2.3 px wide at 16 px. Tune it in the prototype, but hold the 16 px minimums below.
- **Colour:** the slash is `#2563EB` on the white sheet (Light) and on the `#0A0A0A` sheet (Dark). No gradient and no second blue.
- **No box-in-box rule (hard):** the macOS squircle sheet is the only container. Inside it there is no rect, rounded rect, frame, border, document or page shape, badge, circle, inner sheet, or drop shadow that reads as a tile. The slash never touches or crosses the sheet edge, so it never cuts the sheet into shapes that look like a second box. The favicon and the one-color mark follow the same rule. The mark is the slash alone, with no backing shape.
- **Format-neutral:** no TeX, Markdown, `M↓`, `{}`, page or pen motif. The app edits LaTeX, Markdown, plain text and other text files.
- **Original:** drawn from scratch in `gen.py`. No font glyph is outlined into the icon, and no third-party slash logo is traced.

## Smallest complete change set

**Phase 0: freeze the rollback point (before any Phase 2 commit)**
- Put an annotated tag, `art-libreweave-weave`, on the last commit that ships the weave. That is the only copy kept. No weave files stay in the tree, so stale brand art cannot ship.

**Phase 1: internal prototype (allowed during the hold)**
1. Add `art/prototype/virgule/gen.py`, a copy of the generator with the slash geometry. It writes into `art/prototype/virgule/` only: `AppIcon.icon` (with the layers below), flat icons, one-color marks, a favicon, and a wordmark SVG.
2. Icon Composer structure (`icon.json`):
   - Sheet `fill-specializations`: Light `#FFFFFF`, Dark `#0A0A0A`, Tinted `#0A0A0A`, the same scheme the weave uses.
   - One group with one layer, `slash`. Its `image-name-specializations` are `slash-blue.svg` for Light and Dark, and `slash-white.svg` for Tinted. The Mono white slash is required: with the weave, `#2563EB` in Tinted dark measured only 53 against a sheet of 36, which would be too weak for a single-element mark.
   - `glass: false`, shadow none, specular off, translucency off. Clear and Tinted are left to macOS, with no in-app setting, as today.
3. Extend the prototype copies of `review.sh` and `appearance-check.m` to measure the **mark** as well as the sheet. Sample the slash centre and the sheet beside it in every mode at 16, 32 and 256 px.
4. Wordmark: "Virgule" in SF Pro Bold, editable live-text SVG plus an outlined export, ink or paper only (no blue in the word). Lockup with the slash mark on its left, with the name kept separate from the icon geometry.
5. Review the prototype against the acceptance checks and present `review.png` to the coordinator.

**Phase 2: replace (only after the name review passes and the prototype is accepted)**
1. Move the prototype generator into `art/tools/gen.py`, replacing the weave. Remove `Assets/lines-*.svg` and `threads.svg`, add `slash-blue.svg` and `slash-white.svg`, and rewrite `icon.json`.
2. Regenerate `art/source/app-icon-{white,black}.svg`, `mark-{white,black}.svg` and `landing/icon.svg`. The favicon keeps the `prefers-color-scheme` sheet switch and gets `aria-label="Virgule"`. Add `art/source/wordmark-*.svg`.
3. Promote the measuring checks from Phase 1 step 3 into `art/tools/review.sh` and `validate.sh`, and rename the throwaway bundle.
4. Build the Backend-renamed `.app`. Regenerate `built-app-evidence.txt` and `review.png` from that build.
5. Rewrite `art/README.md` and `art-direction.md` for the slash mark. Record LibreWeave and the weave as the former brand, with the rollback tag.
6. Hand the favicon, wordmark and a social-image mark to Landing and Brag. They recapture screenshots, poster, GIF and video once the new icon and name are in a shipped build. Art checks every frame for the slash icon, the single blue and the BB-8.

## Acceptance checks (must all pass before Phase 2 merges)

All brightness values are 0–255. They are measured by the extended `appearance-check` (IconServices: light, dark, clear-light, clear-dark) and by `ictool` (tinted-light, tinted-dark) on the compiled bundle, at 16, 32 and 256 px.

| Mode | Sheet | Slash | Pass if |
| --- | --- | --- | --- |
| Light | white, ≥ 250 | `#2563EB` ±4 per channel at 256 px | Slash/sheet contrast ≥ 4.5:1 (target 5.17:1) |
| Dark | `#0A0A0A`, ≤ 16 | `#2563EB` ±4 per channel at 256 px | Contrast ≥ 3:1, the WCAG 1.4.11 minimum for graphics (target 3.83:1) |
| Clear light | system glass | white (Mono) | Slash − sheet ≥ 60 |
| Clear dark | system glass | white (Mono) | Slash − sheet ≥ 60 |
| Tinted light | user tint | white (Mono) | Slash − sheet ≥ 50 |
| Tinted dark | user tint | white (Mono) | Slash − sheet ≥ 50. This is the weakest mode and is checked at 16 px too. |

- **16 and 32 px:** the slash is one continuous stroke at least 2 px wide at 16 px, with no broken anti-aliasing gaps and no caps clipped by the squircle mask, in all six modes. It is checked zoomed in `review.png`.
- **Legacy `.icns` (macOS 14–25):** the light render passes the Light row.
- **actool:** `validate.sh` passes with no warnings. `assetutil --info` on the built `Assets.car` lists `IconImageStack` for `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua` and `ISAppearanceTintable`. Info.plist still has `CFBundleIconName = AppIcon`.
- **No box-in-box:** the generated layer SVGs and `landing/icon.svg` contain exactly one `<rect>`, and only in the favicon and flat icons, where it is the sheet. The `.icon` layer files contain only the slash path. `icon.json` has one group and one layer. A visual review at 16 and 512 px finds no enclosed inner shape.
- **Favicon:** in Safari, Chrome and Firefox, light and dark `prefers-color-scheme` show a white or black sheet with the blue slash, and match the app icon render.
- **One-color marks:** the black and white slash read at 16 px on white, `#0A0A0A` and a mid-grey.
- **One blue:** across `art/`, `landing/`, `NativeLatex/Assets.xcassets` and `Theme.swift`, the only blue hex is `2563EB`. BB-8 orange is the only other accent.
- **No stale brand:** `grep -ri "libreweave\|weave\|thread"` over `art/source`, `art/tools`, `NativeLatex/AppIcon.icon` and `landing/icon.svg` returns nothing. No shipped screenshot, poster, GIF or video frame shows the weave or "LibreWeave".

## Sequencing and dependencies

1. Phase 0 tag, then Phase 1 prototype, during the hold.
2. Coordinator: name review passes and prototype is accepted. This gates Phase 2.
3. Phase 2 steps 1–3 can land with or before the Backend target and bundle rename. Step 4 needs the renamed `.app`.
4. Landing's hostname switch needs the favicon and wordmark from step 2. Brag's recapture needs a shipped build with the new icon and the UX/Backend strings.

## Migration and rollback risks

- **Icon cache:** the pixels now change. After the new app replaces the old one, the Dock, Finder and Launchpad may show the weave until IconServices refreshes. `built-app-evidence.txt` already records a cached dark icon surviving an appearance toggle. Backend owns app replacement and any cache reset. Art's validation uses the throwaway bundle and `appearance-check`, which do not depend on the system cache.
- **Document icons:** no custom document icons exist today. Finder's file icons for `.tex`, `.md` and others badge with the app icon, and they update along with it.
- **Favicon and social cache:** browsers and link-preview caches keep the weave for a while. Landing owns cache-busting and the `og:image` URLs.
- **Weak Clear/Tinted:** a single blue element greys to a low-contrast smear, which is why Mono uses the white slash and why the table's minimum differences are hard gates.
- **Rollback:** `git checkout art-libreweave-weave -- art/tools/gen.py NativeLatex/AppIcon.icon art/source landing/icon.svg art/exports art/README.md docs/workspaces/art/art-direction.md`, then `art/tools/build.sh` and `validate.sh`. The weave stays recoverable from the tag only. `AccentColor`, `Theme.swift` and BB-8 never change, so rollback cannot break the palette.

## Coordinator decisions

1. Who runs the name and mark review, and what counts as a pass (App Store collision, Canadian VIRGULE listing, other regions, slash-logo similarity)? Nothing in Phase 2 starts without it.
2. Approve the brief: one blue slash with rounded caps, white in Mono, about 150 px stroke at about 65–70°. Square or angled caps would be a design change to decide here, not in review.
3. Should the landing header use the wordmark lockup, or the icon plus text `<span>`?
4. Media file names: rename `libreweave-*` in `landing/media/`, or keep them until Landing's redirects are live? Art recommends keeping them until then.
5. Confirm that Brag and Landing recapture all screenshots and video after the new icon ships.

## Blockers

None for planning. All public work is held behind decision 1.
