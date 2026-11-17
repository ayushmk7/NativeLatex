# Adversarial Claude brief

Review implementation branches for concrete errors. Run a focused reproduction and report file/line, impact, and the smallest fix. Coordinate disjoint repairs on the Adversarial branch after the orchestrator merges implementation work. Verify each repaired behavior with a meaningful check. Do not read real `.env` files or use real API keys; fake credentials are test doubles only. Never silently replace a user's document during testing.
