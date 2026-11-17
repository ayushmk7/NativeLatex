# Landing workspace plan

Status: static implementation complete locally · 2026-11-17

The landing page is a single static page in [`landing/`](../../../landing/README.md), ready for Vercel with that directory as the project root. It uses no framework, build service, account, analytics, or form. While the Mac app does not exist, its main action links to the GitHub project and clearly says there is no download. The window graphic is labeled as a concept preview.

The [Downloads frontend design guide](/Users/ayush/Downloads/distinctive-frontend.md) informed the serif/sans type contrast, purposeful entrance sequence, and coordinated light/dark colors. The user's [Website BB-8 control](/Users/ayush/Downloads/Website/src/components/v2/BB8Toggle.astro) informed the rolling-droid theme switch; the landing page uses a smaller, newly drawn CSS version with the app's black/white and royal-blue palette. The Mac app needs its own native control under the [art plan](../art/art-direction.md).

Before publishing: recheck the app name, preview both themes at desktop and narrow widths, test keyboard/screen-reader switch behavior, then connect the GitHub repository in Vercel with `landing` as Root Directory and **Other** as framework. No download button or release claim appears until a signed and notarized artifact passes the [deployment gate](../../deployment-plan.md).
