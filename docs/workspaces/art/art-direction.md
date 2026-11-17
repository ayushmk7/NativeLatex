# Art direction: NativeLatex for Mac

Status: brief; first assets merged · 2026-11-17. **LibreLeaf** is the working app name (NativeLatex stays the repository and project path); the mark must work without a wordmark. The icon set and `AccentColor` are in `NativeLatex/Assets.xcassets` and pass `art/tools/validate.sh`; see [art/README](../../../art/README.md).

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

## App icon: concepts and decision

| Concept | Visual | Assessment |
| --- | --- | --- |
| **A. Brace to page** | A bold source brace merges with a crisp typeset sheet. | Best expression of source becoming output, independent of the working name. |
| **B. Typesetter's block** | Rules of text around one large mathematical glyph. | Attractive at large size; fine rules risk vanishing in the Dock. |
| **C. Folded manuscript** | One folded sheet with a monogram. | Familiar but generic and tied to a name that may change. |

**Choose A.** The square 1024 × 1024 source has a centered, bold brace at roughly the left third and a page beginning just right of center. Let the shapes overlap slightly so they read as one source-to-output symbol. Use a black or white field according to the icon appearance, a contrasting page, and royal blue for the brace or the connection between shapes. Keep two broad text rules on the page at most. No literal code, tiny equations, pen nib, faux app screenshot, or multicolor gradient. Make two or three editable layers: background, page, and brace. Inspect the system mask rather than drawing rounded corners into the artwork.

Create default and dark reviews, plus clear and tinted appearance checks, from the same central geometry. Produce custom variants only if system-generated ones lose the mark. Apple's [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) recommends simple centered content and square unmasked layers for Icon Composer.

## Appearance switch: adapt the Website reference

The actual reference is [BB8Toggle.astro](/Users/ayush/Downloads/Website/src/components/v2/BB8Toggle.astro) and [bb8.css](/Users/ayush/Downloads/Website/src/components/pro/opt4/bb8.css). Its pill is approximately 10.625:5.625 in aspect ratio; a round robot moves from left to right while the backdrop changes from clouds and desert to stars and a dark sky. The Website also uses orange accents, tan scenery, many small decorative elements, and staggered 0.2–0.8 second transitions. These details are useful as reference, but too busy and warm for the requested Mac palette.

**Native visual translation:** retain the instantly recognizable pill, rounded robot body, small dome head, and rolling left-to-right travel. In light mode, use a white pill with a black outline, one minimal blue sun or blue horizon mark, and a white/black robot with blue seams. In dark mode, use a black pill with a white outline, two or three white stars, and the same robot at the right. A short 180-degree body rotation can imply travel; head and antenna stay upright. Keep the fixed control large enough for pointer use and visual recognition, while the surrounding toolbar remains sparse. The switch is an appearance control, never the app icon or loading animation.

Keep a still frame for each state. When Reduce Motion is on, swap state without rolling or scenery travel. When Increase Contrast is on, strengthen the pill border and robot silhouette. The focused state uses a visible royal-blue ring outside the pill. The light/dark state must also be conveyed through the control label and accessible value; interaction and keyboard behavior are specified in the [UX plan](../ux/ux-plan.md). Do not embed the Website's CSS or web checkbox inside the native app; redraw the small scene as native/vector artwork so it scales cleanly and follows macOS appearance settings.

The reference source credits **Uiverse.io / Galahhad**. If implementation copies any original artwork or code, preserve the applicable license notice and credit; Uiverse's [gallery README](https://github.com/uiverse-io/galaxy) describes its MIT terms. A near-exact BB-8 character likeness has separate brand-rights questions, so the planned shipped art is an original rolling-robot interpretation.

## Brand assets to hand off

| Asset | Source and export |
| --- | --- |
| Mac app icon | Editable vector layers, Icon Composer project, and app asset catalog; include default/dark/clear/tinted review sheet. |
| Standalone source-to-page mark | SVG/PDF vector for About, help, and project materials, plus one-color black and white versions. |
| Wordmark lockup | Editable type source and outlined export; keep name separate from icon geometry. |
| Appearance-switch art | Native/vector source for light, dark, focused, increased-contrast, and reduced-motion still states. |
| Palette sheet | Role names, light/dark values, contrast results, and examples on actual Mac controls. |

Keep source files in the future art implementation workspace and exports in the app asset catalog. The present document is the brief; no artwork is being generated in this planning pass.

## Review checklist

1. Check the icon at 16, 32, 64, 128, and 512 px in light and dark Dock contexts. At 32 px, brace and page must remain distinct.
2. Inspect icon variants in Icon Composer for clipping, weight, and legibility; test the one-color mark at 16 px.
3. Review the switch as two stills and a short transition at actual toolbar size. The robot must remain readable without clouds, tan ground, or orange markings.
4. Test the switch with keyboard focus, VoiceOver, Reduce Motion, Increase Contrast, and grayscale. UX owns behavior; art owns visible state and silhouette.
5. Compare a light and dark editor window with an actual PDF. The source and output should dominate; the switch and blue accent should be clear but secondary.

## Scope

Mac only. No iPhone/iPad icon targets, theme packs, textured editor backgrounds, or page-load animation are planned. The icon and switch are the only custom illustration work in the first visual pass.
