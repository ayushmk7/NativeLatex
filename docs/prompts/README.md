# Prepared Claude workspace prompts

These files are task briefs for the linked Herdr spaces. Claude sessions are running in the implementation spaces and in Adversarial. Each session inspects its own checkout and changes only its workspace branch. Coordinate shared product decisions through `docs/product-plan.md` and merge only after review.

| Space | Brief |
| --- | --- |
| NativeLatex | [Coordinator](coordinator.md) |
| Art | [Art](art.md) |
| UX | [UX](ux.md) |
| Backend | [Backend](backend.md) |
| Integrations | [Integrations](integrations.md) |
| Landing | [Landing](landing.md) |
| Adversarial | [Adversarial](adversarial.md) |

The Claude terminals use `claude --dangerously-skip-permissions` because the owner requested it. That flag changes Claude's confirmation behavior; these briefs still state scope and review gates. The live task prompts were sent through Herdr; these files are the durable scope record.

The [Virgule candidate planning brief](virgule-planning.md) assigns a planning-only rebrand review to Art, UX, Backend, Integrations, Landing, Brag, Markdown UX and Adversarial. Its [coordinator plan](../virgule-rebrand-plan.md) collects the results; LibreWeave remains the shipped name.
