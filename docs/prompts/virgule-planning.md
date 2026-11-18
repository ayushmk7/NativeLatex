# Virgule candidate: workspace planning brief

**Status:** planning only. Virgule is a candidate name, not an approved rebrand. Do not rename code, assets, bundle identifiers, app installations, URLs, repositories, or releases. Do not publish or deploy anything.

Use the latest `main` checkout at `/Users/ayush/Downloads/My Projects/NativeLatex` as the source of truth. Herdr worktree branches may lag behind it. Read the relevant code, assets, existing plans, and checks before writing. Create only your assigned plan file in your own Herdr worktree under `docs/workspaces/<space>/virgule-plan.md`, then commit that file on your branch. Do not edit another workspace's files. Keep recommendations limited to the requested rebrand and distinguish existing behavior from planned features.

The shared visual constraints are black/white light and dark appearances, one accent `#2563EB`, an adaptive macOS icon with a clear single mark and no nested box, and the BB-8 appearance control. The app is native Mac only. It opens and edits LaTeX, Markdown, plain text, and other supported text files; names must not imply it only views or only handles one format. The installed app, file associations, recent documents, settings, build output, and user files must remain safe through any eventual rename.

Name gate: an existing iPhone/iPad news app is called Virgule (Apple App Store ID 1245101112), and a preliminary search found a Canadian VIRGULE trademark listing mentioning software. Do not assert the name is cleared or that this listing applies to this app. Include a public-rename hold pending proper name review, a reversible internal prototype path, and a fallback if Virgule is rejected.

Each plan should contain: current touchpoints with file paths, the smallest complete change set, sequencing/dependencies, validation that would prove completion, migration or rollback risks, and decisions the coordinator must make. No implementation or tests are requested in this planning pass.

| Herdr space | Plan focus |
| --- | --- |
| Art | Wordmark, macOS Icon Composer light/dark/tinted/clear variants, favicon, screenshots, generated assets, one-blue consistency. |
| UX | Window/menu/settings/file-open copy, onboarding and accessibility, appearance, default file handler continuity, user-facing migration. |
| Backend | Xcode target/scheme/module/bundle ID, Info.plist, preferences and build-output migration, tests, installed app replacement, signing/notarization/release. |
| Integrations | Conversion/export/import and Google Docs/LibreTexts text, auth/config identifiers, cross-format data guarantees. |
| Landing | New hostname and old-site redirect strategy, copy, theme, SEO/social images, video/media URLs, GitHub Pages workflow and DNS/release gates. |
| Brag | README, screenshots, demo capture/video/GIF/poster, metadata and embedded media references, avoiding stale brand in distributable assets. |
| Markdown UX | Markdown Read/Write/source UI naming, menu/toolbar strings, screenshots, tests and accessibility specific to Markdown. |
| Adversarial | Independently challenge all rebrand assumptions, name collision evidence, migration/data-loss paths, rollback, release/check gaps. |

Work independently. The coordinator will reconcile plans and bring only planning commits to `main`.
