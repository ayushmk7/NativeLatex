# Adversarial workspace

The linked Herdr **Adversarial** workspace contains four Claude sessions. Their sole job is to find concrete defects, reproduce them, and drive repairs before release. They review implementation worktrees without modifying those branches. After integration, they can repair disjoint issues on the Adversarial branch; the orchestrator merges and reruns checks.

| Pane | Scope | Required evidence |
| --- | --- | --- |
| Functionality | File opening, editing, saving, LaTeX/Markdown run, preview, multiple windows | Reproduction and focused test |
| Security | Process arguments, paths, temp files, external changes, credentials, untrusted content | Impact and minimal safe fix |
| UX Access | Design match, theme switch, keyboard, VoiceOver, contrast, reduced motion, responsive landing | Screenshot or accessibility check |
| Build Release | Xcode, assets, conversion fixtures, file associations, static deployment, signing claims | Command/output and artifact check |

Only real failures become repair tasks. A fake key can exercise a test double, but it cannot prove live Google Docs, AWS, or Vercel access. Public release still needs valid signing and deployment credentials. The app's local workflow must pass without them.
