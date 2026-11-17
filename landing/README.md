# LibreLeaf landing page

Static, dependency-free landing page for the planned Mac app (repository and paths still use the NativeLatex name). The page links to the repository and says there is no download yet; the app window is labeled as a concept illustration. Replace the GitHub call to action with a download only after a signed and notarized Mac build passes the [deployment gate](../docs/deployment-plan.md).

## Look

Matches the owner's Website and Internship pages: white/black surfaces, one royal-blue accent (`#4169E1`, `#8BA6FF` as text in dark mode), system sans type, hairline dividers, pill buttons. `icon.svg` is the Art branch's small-size app icon master (`art/source/app-icon-small.svg`) with the viewBox cropped to the icon body.

The theme switch is the same BB-8 toggle those two sites use. `bb8.css` is copied verbatim from the Internship frontend (artwork by Galahhad on Uiverse.io, MIT); `styles.css` only sizes it, outlines it, and keeps its checkbox keyboard-focusable. The web toggle is separate from the Mac app's original appearance-switch art in the [art plan](../docs/workspaces/art/art-direction.md).

## Local preview

From the repository root, run `python3 -m http.server 4173 --directory landing` and open `http://localhost:4173`.

## Vercel

Import the GitHub repository and set **Root Directory** to `landing`. Choose **Other** as the framework preset; there is no build command or output folder. Vercel Hobby is for personal, non-commercial use; check the [deployment plan](../docs/deployment-plan.md) before publishing.
