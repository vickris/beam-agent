# Working Plans

Use a plan for work that spans multiple files, changes a public contract, affects OTP/process behavior, or has meaningful release risk. Skip a standalone plan for a trivial, isolated fix.

## Workflow

1. Create a plan in `.agent/plans/` from [PLAN_TEMPLATE.md](plans/PLAN_TEMPLATE.md); use a short, descriptive kebab-case filename.
2. State the goal, constraints, affected areas, ordered tasks, and verification criteria before implementation.
3. Update task status as work proceeds. Keep the plan concise and useful rather than copying the entire conversation.
4. Before finishing, record checks run, outcomes, and any unresolved follow-up. Do not mark unchecked validation as passed.
5. Keep completed plans for project history unless they contain temporary or sensitive information; do not store secrets in plans.
