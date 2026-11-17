# Art direction: LibreWeave for Mac

Status: adaptive icon shipped · 2026-11-17. **LibreWeave** is the working app name (NativeLatex stays the repository and project path); the mark must work without a wordmark. The app icon is `NativeLatex/AppIcon.icon`; `AccentColor` is in `NativeLatex/Assets.xcassets`. All pass `art/tools/validate.sh`; see [art/README](../../../art/README.md).

## Visual thesis

Use a precise ink-and-paper identity: white and black form almost the entire interface, with the one brand blue, **`#2563EB`**, marking the active action, selection, and brand. The character comes from a distinctive app icon, strong but readable typography, and a small animated appearance switch. The writing and PDF surfaces stay calm during long sessions.

This interprets the four-vector approach in the supplied [frontend design guide](/Users/ayush/Downloads/distinctive-frontend.md): typography, color, motion, and background should form one system. Its web examples of thin body type, page-load choreography, and textured gradients are poor fits for a dense native editor, so the Mac plan uses strong headings, one accent, purposeful switch motion, and flat document surfaces.

## Core palette and type

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Main surface | White `#FFFFFF` | Black `#000000` | Editor surroundings and primary window areas |
| Secondary surface | Near-white `#F4F4F4` | Near-black `#141414` | Sidebar, toolbar, problems panel |
| Primary ink | Near-black `#0A0A0A` | White `#FFFFFF` | Body and controls |
| Divider | Neutral gray, adjusted for contrast | Neutral gray, adjusted for contrast | Pane edges, never decorative heavy borders |
| Brand blue | `#2563EB` | `#2563EB` (same value; also high contrast) | Build action, selected tab, links, focus, small brand details |

The blue is one value on every surface and in every appearance. A local relative-luminance check measured:

| Colour | Against | Ratio |
| --- | --- | --- |
| `#2563EB` | white (and white text on a `#2563EB` fill) | 5.17:1 |
| `#2563EB` | black | 4.06:1 (large text, fills and graphics) |

Still validate actual controls, focus, and increased-contrast mode. Inactive chrome and errors must remain understandable in grayscale; never encode build status by blue alone. PDF paper stays white in both appearances because it represents the actual output. Respect native macOS material and semantic colors where they control legibility, then apply the brand blue to chosen interactive states. The app's own colour tokens live in the Design package (`Theme.swift`), which Design owns. Art sets only the icon, favicon and `AccentColor`. Apple's [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) calls for appearance and contrast testing.

Use San Francisco for ordinary Mac controls and a clear monospaced face for source. Give start-screen titles and major section labels a bolder editorial weight; keep editor text regular and adjustable rather than using the guide's ultra-thin body example. The wordmark, if used, can pair a bold sans name with the standalone icon mark. Avoid downloaded web fonts in the app's core interface.

## App icon: woven sheet (current)

The first concept (a brace over a page on a black field) read as a box inside a box. The current icon fixes that: **the macOS silhouette itself is the sheet**, with no inner page or frame. On it, two lines (wefts) weave over and under two blue threads (warps). Each crossing alternates, so it reads as fabric rather than a `#`. There are no letters.

| Appearance | Sheet | Lines | Threads |
| --- | --- | --- | --- |
| Light | `#0A0A0A` | `#FFFFFF` | `#2563EB` |
| Dark | `#FFFFFF` | `#0A0A0A` | `#2563EB` |
| Clear light / dark | System glass (replaces our fill) | White | Mid gray, derived from `#2563EB` |
| Tinted light / dark | User's tint | White / tint | Tint, lighter / darker |

macOS picks Clear and Tinted from the user's icon-style setting and composites Clear's backdrop translucency live in the Dock. In static renders, Clear is the same opaque neutral glass for our icon and for Apple's own icons. The app forces no alpha and needs no setting. There is no Mono (`tinted`) override: `#2563EB` already greys between the Clear sheet and lines; measurements are in art/README. Tinted dark remains the lowest-contrast mode, readable at 32 px and up.

The landing favicon follows the same rule through `prefers-color-scheme`: black sheet on light pages, white sheet on dark pages.

- **Grid:** Apple's macOS icon template: one 824 px silhouette, 100 px inset, 185 px corner radius on a 1024 canvas.
- **One geometry for every size:** macOS draws the `.icon` at every size from a single vector, so the mark uses a 2×2 weave. It spans 480 px of the 824 px body (58%), the same glyph proportion as Apple's own icons such as Calculator; an earlier full-bleed weave (78%) looked oversized next to them. Coordinates are multiples of 48: 3 px strands at 32 px; at 16 px the weave is soft but still reads. An earlier 3-line weave looked richer at 512 px but blurred into a clump at 16 px, so it was removed.
- **Source:** everything is generated by `art/tools/gen.py`.

**How appearance variants work on macOS (verified 2026-11-17, Xcode 27.2, macOS 27.3):**

- A macOS `.appiconset` has no dark slot. actool silently drops `luminosity: dark` entries.
- The Icon Composer document `NativeLatex/AppIcon.icon` gives real variants:
  - `fill-specializations` sets the sheet colour per appearance.
  - `image-name-specializations` swaps the lines layer between white and black.
- In the built app, `Assets.car` holds `IconImageStack` renditions for `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua` and `ISAppearanceTintable`. The last drives both Clear and Tinted. `icon.json` has no `tinted` (Mono) specialization, so actool derives the tintable stack from the default layers.
- From the same `.icon`, actool also generates the legacy `AppIcon.icns` (black sheet) for macOS 14–25 and the flat `Icon Image` renditions.
- When `AppIcon.icon` exists, actool ignores a same-named `.appiconset`: removing it left `AppIcon.icns` byte-identical. The project's `.appiconset` was deleted.

## Appearance switch: the Website BB-8 (intentional palette exception)

The shipped switch is the user's Website BB-8 toggle, kept in its own orange and gradient colours. The rest of the app stays black, white and `#2563EB`; this switch is the one deliberate exception.

- **Landing page:** `landing/bb8.css` is `Website/src/components/pro/opt4/bb8.css` with the artwork unchanged. It replaces that file's header comment and adds ten hover rules: seven `.bb8-toggle__checkbox:hover` rules for the head and antennae, then three `.bb8:hover` resets.
- **Mac app:** `NativeLatexDesign/BB8Toggle.swift` draws the native version.
- **Ownership:** Design and UX own the switch's code, behaviour and accessibility. Art supplies no separate switch artwork.
- **Credit:** the source credits **Uiverse.io / Galahhad** (MIT terms per Uiverse's [gallery README](https://github.com/uiverse-io/galaxy)). Keep that notice wherever the artwork or code is copied.

An earlier plan for a black-and-white "original rolling robot" redraw was dropped, and its stills were deleted on 2026-11-17.

## Brand assets to hand off

| Asset | Source and export |
| --- | --- |
| Mac app icon | `NativeLatex/AppIcon.icon` (light/dark layers); `art/exports/review.png` with default/dark/tinted/clear renditions. Done. |
| Standalone woven mark | SVG/PDF vector for About, help, and project materials, plus one-color black and white versions. |
| Wordmark lockup | Editable type source and outlined export; keep name separate from icon geometry. |
| Palette sheet | Role names, light/dark values, contrast results, and examples on actual Mac controls. |

Keep source files in the future art implementation workspace and exports in the app asset catalog. The present document is the brief; no artwork is being generated in this planning pass.

## Review checklist

1. Check the icon at 16, 32, 64, 128, and 512 px in light and dark Dock contexts (`art/tools/review.sh`). At 16 and 32 px, the blue/white over-under crossings must remain distinct.
2. Inspect icon variants in Icon Composer for clipping, weight, and legibility; test the one-color mark at 16 px.
3. Compare a light and dark editor window with an actual PDF. The source and output should dominate; the BB-8 switch and blue accent should be clear but secondary.

## Scope

Mac only. No iPhone/iPad icon targets, theme packs, textured editor backgrounds, or page-load animation are planned. The icon is the only custom illustration Art owns; the BB-8 switch reuses the Website artwork.
