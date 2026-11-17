# Landing workspace plan

Status: refreshed to match owner sites, LibreLeaf name · 2026-11-17

The landing page is a single static page in [`landing/`](../../../landing/README.md), ready for Vercel with that directory as the project root. It uses no framework, build service, account, analytics, or form. While the Mac app does not exist, its main action links to the GitHub project and clearly says there is no download. The window graphic is labeled as a concept preview.

The visible product name is **LibreLeaf**; the repository keeps the NativeLatex name. The look follows the owner's Website and Internship pages (black/white, royal-blue accent, system sans, hairlines, pill controls) rather than the earlier serif treatment. The theme switch reuses the exact Uiverse BB-8 toggle shipped on both of those sites, with its MIT credit; the Mac app still needs its own original native switch under the [art plan](../art/art-direction.md). The favicon and header mark come from the Art branch's small-size icon master.

Before publishing: recheck the app name, preview both themes at desktop and narrow widths, test keyboard/screen-reader switch behavior, then connect the GitHub repository in Vercel with `landing` as Root Directory and **Other** as framework. No download button or release claim appears until a signed and notarized artifact passes the [deployment gate](../../deployment-plan.md).
