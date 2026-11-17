# NativeLatex landing page

Static, dependency-free landing page for the planned Mac app. The site deliberately links to the repository while no signed Mac download exists. Its app window is labeled as a concept preview.

## Local preview

From the repository root, run `python3 -m http.server 4173 --directory landing` and open `http://localhost:4173`.

## Vercel

Import the `NativeLatex` GitHub repository and set **Root Directory** to `landing`. Choose **Other** as the framework preset; there is no build command or output folder. The page uses plain HTML, CSS, and JavaScript. Vercel Hobby is for personal, non-commercial use; check the [deployment plan](../docs/deployment-plan.md) before publishing. The download link should replace the GitHub CTA only after the signed and notarized Mac artifact is verified.

The small rolling-droid theme control is a fresh CSS interpretation of `/Users/ayush/Downloads/Website/src/components/v2/BB8Toggle.astro` and its CSS, recolored for NativeLatex. It is not the Mac app control; that requires a native implementation under the [art plan](../docs/workspaces/art/art-direction.md).
