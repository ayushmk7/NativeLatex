# Art direction: LibreWeave for Mac

Status: icon redone for LibreWeave · 2026-11-17. **LibreWeave** is the working app name (NativeLatex stays the repository and project path; the Xcode product is still named LibreLeaf until the app owners rename it); the mark must work without a wordmark. The icon set and `AccentColor` are in `NativeLatex/Assets.xcassets` and pass `art/tools/validate.sh`; see [art/README](../../../art/README.md).

## Visual thesis

Use a precise ink-and-paper identity: white and black form almost the entire interface, with **royal blue** marking the active action, selection, and brand. The character comes from a distinctive app icon, strong but readable typography, and a small animated appearance switch. The writing and PDF surfaces stay calm during long sessions.

This interprets the four-vector approach in the supplied [frontend design guide](/Users/ayush/Downloads/distinctive-frontend.md): typography, color, motion, and background should form one system. Its web examples of thin body type, page-load choreography, and textured gradients are poor fits for a dense native editor, so the Mac plan uses strong headings, one accent, purposeful switch motion, and flat document surfaces.

## Core palette and type

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Main surface | White `#FFFFFF` | Black `#000000` | Editor surroundings and primary window areas |
| Secondary surface | Near-white `#F4F4F4` | Near-black `#141414` | Sidebar, toolbar, problems panel |
| Primary ink | Near-black `#0A0A0A` | White `#FFFFFF` | Body and controls |
| Divider | Neutral gray, adjusted for contrast | Neutral gray, adjusted for contrast | Pane edges, never decorative heavy borders |
| Royal blue | `#4169E1` | Brighter `#8BA6FF` where blue is text or a thin focus ring | Build action, selected tab, links, focus, small brand details |

The blue values are design targets, not a promise that one hex value works on every surface. A local relative-luminance check measured `#4169E1` on white at 4.85:1 and `#8BA6FF` on black at 9.00:1; still validate actual controls, focus, and increased-contrast mode. Inactive chrome and errors must remain understandable in grayscale; never encode build status by blue alone. PDF paper stays white in both appearances because it represents the actual output. Respect native macOS material and semantic colors where they control legibility, then apply the royal-blue brand to chosen interactive states. Apple's [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) calls for appearance and contrast testing.

Use San Francisco for ordinary Mac controls and a clear monospaced face for source. Give start-screen titles and major section labels a bolder editorial weight; keep editor text regular and adjustable rather than using the guide's ultra-thin body example. The wordmark, if used, can pair a bold sans name with the standalone icon mark. Avoid downloaded web fonts in the app's core interface.

## App icon: woven sheet (current)

The first concept (a brace over a page on a black field) read as a box inside a box. The current icon fixes that: **the macOS silhouette itself is the sheet**, with no inner page or frame. On it, two or three "lines of text" (wefts) weave over and under two royal-blue threads (warps). Each crossing alternates, so it reads as fabric rather than a `#`. There are no letters.

| Variant | Sheet | Lines | Threads | Used for |
| --- | --- | --- | --- | --- |
| Dark (shipped) | `#0A0A0A` | `#FFFFFF` | `#4169E1` | Mac app icon in every appearance; landing favicon on light pages |
| Light | `#FFFFFF` | `#0A0A0A` | `#4169E1` | Landing favicon on dark pages; a future Icon Composer light layer |

- **Grid:** Apple's macOS icon template: one 824 px silhouette, 100 px inset, 185 px corner radius on a 1024 canvas.
- **Small size:** the 16 and 32 px slots use a simpler two-by-two weave snapped to the 16 px pixel grid (64 units = 1 px): 2 px strands and 1 px gaps. The over/under crossings stay distinct in the menu bar, Finder lists and the Dock.
- **Geometry:** everything is generated from one table in `art/tools/gen.py`.

**Platform limit, verified 2026-11-17 with Xcode 27.2 on macOS 27.3:** a macOS `.appiconset` has no dark-appearance slot. Entries marked `luminosity: dark` compile without a warning, but actool leaves them out of `Assets.car`: all 11 AppIcon renditions have appearance "any". `NSWorkspace.icon(forFile:)` on the built app returns the same black sheet under Aqua and Dark Aqua (`art/tools/appearance-check.swift`). So the app ships **one universal icon**, the dark one, chosen because it holds up on both light and dark Docks. Real per-appearance icons (default, dark, clear, tinted) need an Icon Composer `.icon` document added to the Xcode target. That is a project change for the app owners; the light SVG layers here are ready for it.

## Appearance switch: adapt the Website reference

The actual reference is [BB8Toggle.astro](/Users/ayush/Downloads/Website/src/components/v2/BB8Toggle.astro) and [bb8.css](/Users/ayush/Downloads/Website/src/components/pro/opt4/bb8.css). Its pill is approximately 10.625:5.625 in aspect ratio; a round robot moves from left to right while the backdrop changes from clouds and desert to stars and a dark sky. The Website also uses orange accents, tan scenery, many small decorative elements, and staggered 0.2–0.8 second transitions. These details are useful as reference, but too busy and warm for the requested Mac palette.

**Native visual translation:** retain the instantly recognizable pill, rounded robot body, small dome head, and rolling left-to-right travel. In light mode, use a white pill with a black outline, one minimal blue sun or blue horizon mark, and a white/black robot with blue seams. In dark mode, use a black pill with a white outline, two or three white stars, and the same robot at the right. A short 180-degree body rotation can imply travel; head and antenna stay upright. Keep the fixed control large enough for pointer use and visual recognition, while the surrounding toolbar remains sparse. The switch is an appearance control, never the app icon or loading animation.

Keep a still frame for each state. When Reduce Motion is on, swap state without rolling or scenery travel. When Increase Contrast is on, strengthen the pill border and robot silhouette. The focused state uses a visible royal-blue ring outside the pill. The light/dark state must also be conveyed through the control label and accessible value; interaction and keyboard behavior are specified in the [UX plan](../ux/ux-plan.md). Do not embed the Website's CSS or web checkbox inside the native app; redraw the small scene as native/vector artwork so it scales cleanly and follows macOS appearance settings.

The reference source credits **Uiverse.io / Galahhad**. If implementation copies any original artwork or code, preserve the applicable license notice and credit; Uiverse's [gallery README](https://github.com/uiverse-io/galaxy) describes its MIT terms. A near-exact BB-8 character likeness has separate brand-rights questions, so the planned shipped art is an original rolling-robot interpretation.

## Brand assets to hand off

| Asset | Source and export |
| --- | --- |
| Mac app icon | Editable vector layers, Icon Composer project, and app asset catalog; include default/dark/clear/tinted review sheet. |
| Standalone woven mark | SVG/PDF vector for About, help, and project materials, plus one-color black and white versions. |
| Wordmark lockup | Editable type source and outlined export; keep name separate from icon geometry. |
| Appearance-switch art | Native/vector source for light, dark, focused, increased-contrast, and reduced-motion still states. |
| Palette sheet | Role names, light/dark values, contrast results, and examples on actual Mac controls. |

Keep source files in the future art implementation workspace and exports in the app asset catalog. The present document is the brief; no artwork is being generated in this planning pass.

## Review checklist

1. Check the icon at 16, 32, 64, 128, and 512 px in light and dark Dock contexts (`art/tools/review.sh`). At 16 and 32 px, the blue/white over-under crossings must remain distinct.
2. Inspect icon variants in Icon Composer for clipping, weight, and legibility; test the one-color mark at 16 px.
3. Review the switch as two stills and a short transition at actual toolbar size. The robot must remain readable without clouds, tan ground, or orange markings.
4. Test the switch with keyboard focus, VoiceOver, Reduce Motion, Increase Contrast, and grayscale. UX owns behavior; art owns visible state and silhouette.
5. Compare a light and dark editor window with an actual PDF. The source and output should dominate; the switch and blue accent should be clear but secondary.

## Scope

Mac only. No iPhone/iPad icon targets, theme packs, textured editor backgrounds, or page-load animation are planned. The icon and switch are the only custom illustration work in the first visual pass.
