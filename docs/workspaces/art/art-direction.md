# Art and icon brief: NativeLatex

Status: planning. **NativeLatex** is a working name; the mark must also work without a wordmark.

## Art objective

Create one recognizable macOS Dock icon for a local LaTeX and Markdown editor: source becomes a polished document. The mark should read at small sizes, sit comfortably among current macOS app icons, and be usable in Finder, Spotlight, and the app's About window. The brand system is deliberately small: the app icon, its central mark, and a restrained wordmark. Interface styling is secondary.

## Concept exploration

| Concept | Visual | Strength | Concern |
| --- | --- | --- | --- |
| **A. Brace to page** | A bold source brace on the left resolves into the edge of a typeset page on the right. | Immediately connects code and document; distinctive silhouette. | Needs careful spacing so it does not read as two unrelated symbols. |
| **B. Typesetter's block** | A compact grid of text rules with one emphasized mathematical glyph. | Strong editorial feel and clear at large size. | Fine text details may disappear in the Dock. |
| **C. Folded manuscript** | A single folded sheet with a large TeX-like monogram. | Simple and familiar document-app language. | Less distinctive; a monogram locks the mark to the working name. |

**Chosen direction: A, brace to page.** It expresses the core action without relying on a temporary name or a tiny formula. Keep B and C only as comparison sketches; do not build three production icon families.

## Production icon specification

- **Composition:** square 1024 × 1024 source canvas. Center a single large mark. The left brace begins at about 27% of canvas width; the page begins at about 43%; their shapes overlap by a small amount to visually connect input and output. Keep the mark within a generous central safe area, then inspect the final system mask in Icon Composer. These measurements are starting proportions for the sketch, not fixed export coordinates.
- **Shape:** one thick, continuous brace with rounded optical joins. One clean page silhouette with a visible top edge and two short, broad text rules. No literal code, tiny mathematical notation, pen nib, or fake screenshot. The brace and page must remain recognizable at a 32 px Dock preview.
- **Depth:** two or three layers at most: background, page, foreground brace. Use subtle separation between layers; avoid a deep 3D stack or heavy drop shadow. Let system rendering supply its own mask and appearance treatment.
- **Palette:** deep ink blue `#173A75` for the brace, warm paper `#F8F5EC` for the page, and a blue-gray `#647895` for the background or secondary detail. These are art-direction targets, subject to visual testing in each appearance. Do not use the icon palette as hard-coded app UI colors.
- **Background:** a simple blue-gray field or restrained gradient with enough contrast for the white page. No border drawn around the square canvas; macOS applies the final rounded mask.
- **Wordmark:** set the working name in a system sans face, medium weight. Pair it with the standalone central mark for a splash or About treatment. Keep the wordmark separate from the app icon so a future name change does not require redrawing the icon.

Apple's current [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) calls for simple centered content, square unmasked layers, and testing across default, dark, clear, and tinted appearances. The source should be prepared for Icon Composer, not flattened into a single screenshot-style icon.

## Required variants and assets

| Asset | Source of truth | Output/use |
| --- | --- | --- |
| Layered app icon | Editable vector source with named background, page, and brace layers | Icon Composer source plus app asset catalog output |
| Appearance checks | Same core mark in default, dark, clear light/dark, and tinted light/dark contexts | Review sheet; custom variants only if automatic versions lose the mark |
| Standalone mark | Same geometry without the square background | About window and documentation |
| Monochrome mark | Single-color vector | Small UI or print contexts where full-color art is unsuitable |
| Wordmark lockup | Editable type and outline-safe export | About window and project materials |

Keep the editable vector file, Icon Composer project, exported asset catalog, and review sheet in the future implementation workspace. SVG/PDF vector exports are appropriate for review; the app build should consume the platform asset catalog. Record the font and color values alongside the source so the art can be regenerated.

## Validation before approval

1. View the icon at 16, 32, 64, 128, and 512 px against light and dark Dock backgrounds. At 32 px, the brace and page must remain separate and identifiable.
2. Inspect the system mask, highlights, and all available appearances in Icon Composer. Check that no important content clips near the corners and that tinted/clear variants preserve the same mark.
3. Place the icon among native productivity apps in a Dock mockup. Check for visual weight, edge contrast, and whether it looks like a document rather than a folder or terminal.
4. Run a grayscale check. The two primary shapes must remain distinguishable without hue.
5. Confirm the monochrome mark works at 16 px and that the wordmark remains readable in the About window.

## Supporting interface styling

Use native macOS toolbar, sidebar, split-view, and menu treatments. Keep the source editor visually quiet and the PDF preview on a neutral canvas with a white page. Use semantic system colors and the user's accent color for app chrome; the blue icon palette is a brand cue, not a forced UI theme. Apple's [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [split-view guidance](https://developer.apple.com/design/human-interface-guidelines/split-views), and [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) support those choices.

## Scope

This is a production brief, not finished artwork. Create the chosen icon and its required assets before visual polish elsewhere. Custom illustrations, theme packs, and animated branding are outside the first release.
