---
name: add-beam-agent-feature
description: Plan and implement a substantial new capability in the BeamAgent Elixir agent runtime.
---

When adding a substantial BeamAgent capability:

1. Read AGENTS.md and the relevant architecture documentation.
2. Identify the existing behaviour boundaries.
3. Do not couple BeamAgent to an application domain.
4. Create or update an ExecPlan.
5. Define acceptance criteria before implementation.
6. Implement one milestone at a time.
7. Run the milestone's validation commands.
8. Do not proceed while validation is failing.
9. Record meaningful architecture decisions.
10. Run `mix precommit` before declaring the feature complete.
